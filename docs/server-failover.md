# Server failover between thinkcenter and m75q

thinkcenter runs every homelab service, the Netbird control plane included.
m75q is its twin. Each of the two can take over everything when the other one
is completely down, and both run the same configuration. This document is the
plan for getting there and the record of how far it got.

## Status

| Step | State |
|------|-------|
| m75q installed with secure boot, TPM unlock and a btrfs root | done |
| m75q data disk named `data`, mounted at `/mnt/data` | done |
| Service state in `/var/lib`, only bulk data on the data disk | done in the modules, thinkcenter pinned to its legacy layout |
| Bulk data copied from thinkcenter to m75q once | done, by hand |
| 1. m75q joins the vpsfree tunnel | done |
| 2.1 `homelab.failover.enable` and an empty `homelab-active.target` | open |
| 2.2 `homelab_active` metric and the standby page | open |
| 2.3 Pinned service user and group IDs | open |
| 2.4 memos on m75q, with alerts and health checks gated on the active host | open |
| 2.5 Remaining group 2 services on m75q, one group per commit | open |
| 2.6 Group 1 monitoring on m75q, its alertmanager silent | open |
| 2.7 One shared server definition for both hosts | open |
| 3. vpsfree upstreams list both hosts | open |
| 4. PostgreSQL streaming replication | open |
| 5. File and bulk data sync | open |
| 6. Promote command | open |
| 7. First switchover to m75q | open |
| 8. thinkcenter reinstalled as the btrfs standby | open |
| 9. One Netbird relay per host | open |

## Goal

- Either machine can fail completely, and the other one runs the whole homelab.
- Both hosts carry the same service configuration. Which one is active is
  runtime state, not configuration.
- Traffic switches on its own. Data that can be lost or diverge only changes
  hands through one deliberate command.
- thinkcenter stays untouched until m75q has taken over. Every change before
  the switchover has to leave thinkcenter's generated system unchanged.
  Monitoring of new targets in its prometheus is the accepted exception.
- vpsfree stays a dumb entry point. It is a VPS and therefore not trusted, so
  everything on it is considered public. It forwards traffic and runs nothing
  that holds a secret or data, which is why no failover piece moves there.

Both machines sit in the same home, so this covers the loss of a machine, not
of the site. The borg backups on vpsfree stay the answer to that.

## What can run on both hosts at once

Netbird routes `192.168.91.0/24` to exactly one routing peer per client. Two
instances behind the same service IP therefore never share load. Running a
service on both hosts only means the second instance is warm and already holds
its own history when traffic moves to it. With that in mind the services fall
into five kinds.

### Independent on both hosts

Each instance keeps its own state and does not need the other host. These
form group 1 and run everywhere all the time.

| Service | How it runs twice |
|---------|-------------------|
| prometheus, blackbox-exporter | each instance scrapes every target on its own, so both hold full history |
| alertmanager | the two instances form a gossip cluster and deduplicate notifications, each prometheus sends to both. The NixOS option `clusterPeers` takes host names and hardcodes port 9094, which needs TCP and UDP opened by hand. No `external_labels` per host, or the alerts stop deduplicating |
| loki | today fluent-bit ships only to the local loki, so each loki holds only its own host's logs. Shipping to both lokis gives each a full copy only while both are reachable. A loki that is down longer than fluent-bit's retries and buffer misses those logs for good |
| immich machine learning | stateless. immich tries the URLs in `machineLearning.urls` in order, since v1.122.0 |
| dashboard, healthCheck, nginx, acme | no state. Both hosts and vpsfree renew the same wildcard certificate, far below the Let's Encrypt limit of five per exact set of names in seven days, and lego's ARI renewals are exempt anyway |
| tunnel | the vpsfree upstreams need it up on both |

Monitoring therefore survives the loss of either host, and shows the outage.

### Single writer on PostgreSQL

vaultwarden, immich, memos, Netbird management, Dex, home-assistant's recorder
and grafana all keep their state in PostgreSQL. None of them can run on the
standby:

- A hot standby is read-only, and every one of them writes at startup through
  migrations or on every login. vaultwarden saves the device on every login
  and token refresh, and Dex writes auth requests and refresh tokens.
- Stock PostgreSQL has no multi-primary mode. Bidirectional logical
  replication has no conflict resolution, and these applications were not
  written for it.
- Pointing the standby's instances at the active host's database over the
  network gives no failover, because the database dies with the host.

Streaming replication keeps their data within seconds, so a promote loses
almost nothing. Dex keeps its signing keys in the database, so tokens it issued
stay valid after a takeover.

grafana is in this group only because of its database. Its dashboards and
datasources are provisioned from the repo, so with a local SQLite database it
could move to group 1. Each instance would then keep its own users, sessions,
OAuth tokens, preferences, annotations and alerting state. grafana's own HA
guide asks for a shared database instead.

### Single writer on local files

jellyfin with its SQLite library, ntfy with its user database, prusa-obico,
mosquitto's persistence and vaultwarden's keys and attachments live in
`/var/lib`. These have no replication protocol, so the standby receives
periodic copies and the services stay stopped there. jellyfin supports only
SQLite. ntfy has an experimental cluster mode, but it requires PostgreSQL and
is marked as not ready for production.

### Stateless, but tied to a single writer

sso-proxy and immich-public-proxy hold no state, yet they only forward to Dex
and immich. They follow their backends into group 2.

### Pinned to hardware

zigbee2mqtt owns the USB coordinator, and home-assistant and mosquitto are
only useful together with it. The printer is attached to one host too. These
need hands during a takeover. A network-attached zigbee coordinator would
remove that, but only one client may use its radio at a time, so zigbee2mqtt
still belongs to group 2. Moving it means moving its data directory and
pointing it at the coordinator, which the sync already covers. mosquitto has
no clustering in its open-source version, only bridges.

### Off both hosts

- **Netbird signal** already runs on vpsfree. It is a stateless broker that
  holds no secret.
- **STUN** comes from Google's public server, which management advertises.
  The STUN stream proxy on vpsfree forwards to a port nothing listens on and
  is removed in step 3.

### Netbird relay

The relay is stateless but needs the relay secret, so it stays on the home
hosts behind the vpsfree stream proxy. The client code in Netbird 0.82.0,
`shared/relay/client`, decides how it can fail over:

- Management hands every client a list of relay addresses. The client connects
  to all of them at once and keeps the first that answers as its home relay.
- Two peers on different home relays still meet. Each learns the other's relay
  through signal and opens an extra connection to it.
- A client tells relays apart by the address each relay announces. Two relays
  behind one address therefore break relaying, because peers on different
  instances believe they share one and never meet.
- When its home relay drops, the client reconnects with a backoff of at most
  60 seconds and races over the whole list again. The docs give no timing,
  this comes from the code.
- Relay tokens are signed with the shared secret and stay valid for 12 hours,
  so any relay accepts tokens from either management server. The docs require
  every relay to share that secret.

Netbird's HA guide says the same: "Do not put Relay instances behind a load
balancer that gives them one shared address." It also notes that a proxy in
front of the relay costs QUIC, which applies to the vpsfree stream proxy.

Two relays can therefore never share `api.krejci.io:33080`, neither round
robin nor as primary and `backup`. A failback would leave old connections on
one relay and new ones on the other.

**Until step 9 the relay follows the active host.** It is part of group 2,
and the standby rejects its port on `wg0` like the others. Nothing changes on
thinkcenter. Between a failure and the promote nothing relays, so peers that
need the relay, such as phones behind carrier NAT, lose each other. Direct
connections keep working through signal.

**From step 9 each host runs its own relay.** Each announces its own address,
either a separate port per host on vpsfree or a separate name per host routed
by SNI, and management lists both. The relay then joins group 1, and relayed
peers move to the surviving relay within about a minute without a promote.
The costs:

- The relay address is the one value that differs between the two hosts.
- The standby carries about half the relayed connections, so rebooting or
  deploying it drops those for up to a minute.
- Each relay is monitored and alerted on its own.
- After 12 hours without management the tokens expire and relaying stops on
  both, exactly as with one relay.

It waits for step 9 because management's relay list is a thinkcenter change,
and because both hosts run the shared configuration only once thinkcenter is
reinstalled.

### Groups

- **Group 1** runs on both hosts: the services under "Independent on both
  hosts".
- **Group 2** runs only on the active host, under `homelab-active.target`:
  Netbird management, the Netbird relay until step 9, Dex, sso-proxy,
  vaultwarden, immich with redis,
  immich-public-proxy, memos, jellyfin, ntfy, home-assistant, mosquitto,
  zigbee2mqtt, prusa-obico, printer, grafana, and the borg backups, so two
  hosts never write to the same repositories and the standby never archives a
  stale copy.

While the standby is not promoted, its nginx answers group 2 on the VPN with a
page that says so, rather than with stale data.

## Why not a fully automatic switch

Netbird can fail over between two routing peers by metric, but it also fails
back the moment the preferred peer returns, and it offers no setting to stay
on the standby. With writable services on both hosts that leads to:

- **Lost writes on failback.** Photos and passwords written to m75q during an
  outage vanish from view when clients return to thinkcenter, and two immich
  or vaultwarden databases cannot be merged.
- **Split brain on partial outages.** Every client picks its routing peer
  from its own connectivity, so during a partial failure some clients write to
  one host and some to the other.
- **A stale control plane.** A standby Netbird management server on an old
  copy of its database lacks the peers, keys and policies added since.

A quorum is possible in principle. vpsfree is a third machine at another site,
so etcd on all three with Patroni could promote PostgreSQL safely: a dead home
host leaves the other one and vpsfree with a majority, and a lost home uplink
leaves the two home hosts with theirs. It still does not pay off:

- Patroni moves only PostgreSQL. The file state, group 2 and the metric swap
  would need a cluster manager such as Pacemaker on top.
- File state is copied periodically, so an automatic takeover would silently
  drop up to one sync interval of changes.
- zigbee and the printer need hands anyway.
- vpsfree would hold etcd peer credentials, which breaks the rule that it
  keeps no secrets that matter.

The design therefore switches traffic automatically and leaves the ownership
of the data to a manual promote. Patroni's own multi-site guide recommends the
same for two sites: a standby promoted by hand once the source is confirmed
down, because one site cannot tell the state of the other.

### NixOS-native alternatives

| Approach | What it covers | nixpkgs 26.05 | Why not |
|----------|----------------|---------------|---------|
| keepalived | a floating IP on one LAN segment | mature module | the service IPs reach clients through Netbird, not the LAN, so the metric swap stays and keepalived adds nothing |
| corosync and pacemaker | moving services and promoting | immature: corosync hardcodes `two_node` with `wait_for_all: 0`, no quorum device module, no `pcs` or `crmsh` | the cluster configuration would be written by hand, and the hardcoded quorum settings allow split brain at startup |
| Patroni with etcd | automatic PostgreSQL promote | usable module | needs a third etcd member on vpsfree with write access to the leader key, and covers only PostgreSQL |
| pg_auto_failover, repmgr | PostgreSQL promote through a monitor | packages only, no module | the monitor would hold node credentials on vpsfree |
| DRBD | synchronous block replication | minimal module | safe only with pacemaker and fencing, and replaces btrfs send |

No public NixOS configuration was found that runs two-node HA with pacemaker
or Patroni. The ones found keep stateful services configured but stopped on
the second host and switch by hand.

## Architecture

### Entry points, switched automatically

- **VPN services on `192.168.91.0/24`.** One Netbird Network with both hosts
  as routing peers, added individually so each has its own metric. The lowest
  metric is the active host. Clients prefer it whenever it is connected and
  fail over when it goes offline. Needs client v0.82.0 or later. See
  https://docs.netbird.io/manage/networks/how-routing-peers-work. Failover is
  immediate only for a clean shutdown or a direct connection. A host that
  crashes while a client reaches it through the relay is noticed only when the
  relay notices, which can take a minute, and traffic is dropped until then.
- **Public entry on vpsfree.** m75q gets its own WireGuard tunnel to vpsfree.
  Everything that goes through the tunnel is TCP: the management API and gRPC,
  the relay, and the SNI passthrough for `share.` and `auth.`. vpsfree lists
  both hosts as equal upstream servers. The standby rejects these ports on
  `wg0` with a TCP reset through a unit that conflicts with
  `homelab-active.target`, so nginx always reaches the active host and never
  splits clients between two relays. The promote never has to touch vpsfree.
  This is the idiomatic way in open-source nginx, which has only passive
  health checks. It needs tuning, see "vpsfree upstreams" below.
- **Netbird signal** runs on vpsfree, so peers that know each other can still
  connect directly while the management server is down. That holds only for
  clients that keep running. A client or device that restarts while management
  is down logs in first and gets no tunnels at all until management is back.

### vpsfree upstreams

From the nginx 1.30 documentation and source:

- A TCP reset is an `error`, and the defaults of `proxy_next_upstream`,
  `grpc_next_upstream` and the stream `proxy_next_upstream` move on to the
  next server.
- One failure marks a server unavailable for `fail_timeout`, 10 seconds by
  default, because `max_fails` is 1 by default. The standby is therefore
  marked failed almost all the time. If the active host then has one timeout
  or a WireGuard hiccup, no server is left, and clients get a 502 or a closed
  connection until `fail_timeout` runs out. The same window can follow a
  promote. A short `fail_timeout` of two or three seconds keeps it small.
- Connect timeouts default to 60 seconds, so every `proxy_pass`, `grpc_pass`
  and stream server needs a short one set explicitly. Today only the SNI
  stream server has 5 seconds.
- gRPC fails over only while connecting. A cached idle connection to a host
  that just died takes the first RPCs with it, and they hang until the client
  gives up.
- Every upstream needs a `zone`, or each worker learns about failures on its
  own.
- The relay and the `/api` location proxy straight to one address today. A
  single address is never marked failed, so both need an upstream group.

The standby keeps SSH open on `wg0`, so it stays reachable through vpsfree.

Every switch resets open TCP connections through the route, because
masquerade is on. Planned switchovers therefore run at night.

### State replication, active to standby

| State | Transport | Loss on takeover |
|-------|-----------|------------------|
| PostgreSQL: vaultwarden, immich, Netbird management, Dex, memos, home-assistant, grafana | asynchronous streaming replication of the whole cluster, the standby is a read-only hot standby | the replication lag, typically under a second, unbounded while the link is down |
| Files in `/var/lib`: home-assistant `.storage`, zigbee2mqtt database, vaultwarden keys and attachments, jellyfin SQLite, ntfy users, prusa-obico, mosquitto | periodic sync | up to the sync interval |
| Bulk data under `/mnt/data`: immich media, jellyfin media, borg repositories | periodic sync | up to the sync interval |
| Secrets | the same agenix secrets, rekeyed for both hosts | none |

The standby pulls. The source accepts the sync key only through a forced
read-only command such as `rrsync -ro`, with root logins limited to forced
commands, so a compromised standby can read but not change the active host.
The receiving side snapshots after every sync, so a deletion on the source can
be rolled back.

File state copied while services run is not guaranteed consistent. SQLite
databases are copied through `sqlite3 .backup` until then. Once both hosts are
on btrfs, snapshots on the source and `btrfs send` replace rsync and make
every copy a point in time. Until thinkcenter is reinstalled, its side stays
rsync.

### PostgreSQL replication

The NixOS module has no replica option. `pg_basebackup -R` writes
`standby.signal` and the connection settings into the data directory, and
`postgresql-setup` skips the `ensure*` statements while `standby.signal`
exists. What the setup needs besides:

- **`wal_log_hints = on`.** Without it or data checksums, a returning old
  primary cannot be rewound with `pg_rewind` and needs a full new base backup.
  thinkcenter's PostgreSQL 16 has neither, and turning it on restarts
  PostgreSQL on thinkcenter.
- **A pinned major version.** Both hosts must run the same major version and
  collation, and today they match only by default.
- **Network and access.** PostgreSQL listens on localhost only. Replication
  needs a listen address on the VPN, a `host replication` line in `pg_hba`, a
  role with `REPLICATION` and a firewall port.
- **WAL retention.** A replication slot with `max_slot_wal_keep_size`, so a
  standby that was down catches up, without letting the slot fill the
  primary's disk.
- **No initdb on a new standby.** The module runs `initdb` when the data
  directory is empty. On a freshly installed standby PostgreSQL must not start
  before `pg_basebackup`, which needs that directory empty.
- **The returning old primary is writable.** It has no `standby.signal`, so
  PostgreSQL starts read-write on the old timeline. The boot gate has to keep
  PostgreSQL itself stopped, not only group 2, until `pg_rewind -R` has made
  it a replica. Commits it had not shipped are lost.

### Service users

Copied files keep their numeric owners. The service users get thinkcenter's
existing user and group IDs pinned in the shared configuration, so a file
means the same on both hosts. No new IDs are introduced.

## Procedures

### Unplanned failure of the active host

1. Netbird and vpsfree move traffic to the standby on their own.
2. Group 1 keeps working. Group 2 shows the standby page. Until step 9 the
   relay is down too, so only directly connected peers reach each other.
3. Reach the standby over Netbird, which signal on vpsfree keeps working, or
   over the LAN, or through vpsfree and its WireGuard tunnel. A phone behind
   carrier NAT needs the relay until step 9, so it may have to use the LAN. A
   device that restarted after management went down has no Netbird tunnels,
   so it needs the LAN too.
4. Run the promote command on the standby.
5. Move the zigbee dongle and the printer to it.

### Promote

The one command does, in order:

1. Shows the replication lag and the age of the last file sync.
2. Stops group 2 and PostgreSQL on the old active host. If the old host is
   unreachable, it refuses unless the operator confirms the old host is off,
   with a flag like `--old-host-down`. The operator is the fence, as
   PostgreSQL's failover docs require some fence.
3. Raises the promotion generation and marks the new host active with it.
4. Runs `pg_promote` and aborts if it returns false.
5. Starts `homelab-active.target`, which also stops the `wg0` reject unit.
6. Swaps the Netbird router metrics through the API, so every client prefers
   the new active host. The management server runs again by then. The API
   token is already an agenix secret. The endpoint is a `PUT` of the whole
   router object, not only the metric.

An alert fires when both hosts report `homelab_active` as 1.

### The old active host returns

At boot a host starts group 2 and a writable PostgreSQL only if its
generation is the highest it can see and the other host is not reachable as
active. A marker alone is not enough: a stale marker during a partition would
give two active hosts, which is the unsafe `wait_for_all: 0` of corosync. A
returning thinkcenter therefore sees m75q with the higher generation, starts
group 1 only, keeps PostgreSQL stopped, and is turned into a replica of m75q
with `pg_rewind -R`. The swapped metrics keep clients on m75q, and its reject
unit keeps vpsfree on m75q. Switching back later is the same promote command
in the other direction, run at night.

This protects against a host coming back after an outage. It does not protect
against both hosts running while unable to see each other. Only a quorum
could resolve that, and the reasons against one are above.

## Implementation steps

Each step deploys without touching thinkcenter's services, except step 7.

1. **m75q joins the tunnel.** Generate its WireGuard key on the host, commit
   the public key, give it its own tunnel address and add it to vpsfree's
   peers. vpsfree's tunnel health check pings every peer, so it reports
   m75q whenever m75q is off.
2. **Shared configuration.** Done in small commits, each deployable on its
   own. thinkcenter's generated system stays as it is, compared with
   `system.configurationRevision` held fixed, apart from new monitoring rules.
   1. `homelab.failover.enable` follows the `homelab.dataDisk.legacyLayout`
      pattern: off on thinkcenter, which keeps starting everything at boot,
      and on for m75q. With it on, group 2 units are wanted by
      `homelab-active.target` instead of `multi-user.target`. Modules list
      their units in an option, the way they register scrape targets. The
      target starts empty, and for now it is started by hand.
   2. The active host exports `homelab_active` for prometheus, and the
      standby answers group 2 vhosts with the standby page.
   3. Service users get thinkcenter's user and group IDs pinned. This comes
      before any service lands on m75q, because NixOS fixes an ID when it
      first creates the user.
   4. memos is the first group 2 service on m75q, chosen because it is small.
      Its alert only fires where `homelab_active` is 1, and its health check
      skips the standby. The later services copy this pattern.
   5. The other group 2 services follow, one dependent group per commit: dex
      with sso-proxy, vaultwarden, ntfy, jellyfin, immich with redis, machine
      learning and the public proxy, home-assistant with mosquitto and
      zigbee2mqtt, prusa-obico with the printer, Netbird management with the
      relay, grafana, and the borg backups. Each needs its secrets rekeyed
      for m75q.
   6. Group 1 monitoring runs on m75q. Its alertmanager stays silent until
      step 8 clusters the two, because clustering changes thinkcenter's
      alertmanager. fluent-bit shipping to both lokis waits for the same
      reason.
   7. Both hosts' `homelab` blocks merge into one server definition. Both
      generated systems stay identical, which proves the refactor.
3. **vpsfree upstreams.** Management API and gRPC, the relay, and the SNI
   passthrough in `tunnel.nix` each go to an upstream with both hosts, instead
   of only the first peer. The standby rejects these ports on `wg0` through a
   unit that conflicts with `homelab-active.target`. m75q needs it before
   vpsfree lists m75q, because otherwise m75q drops these ports instead of
   rejecting them. The dead STUN stream proxy goes.
4. **PostgreSQL replication.** m75q becomes a hot standby of thinkcenter,
   with everything listed under "PostgreSQL replication". `wal_log_hints`
   restarts PostgreSQL on thinkcenter.
5. **File and bulk sync.** The restricted pull channel, a timer on the
   standby, and snapshots on the receiving side.
6. **Promote command.** The steps above as one script, with the metric swap.
7. **First switchover.** At night: promote m75q, move the zigbee dongle and
   the printer, check every service. thinkcenter must not boot its old
   configuration afterwards, because with `homelab.failover.enable` off it
   starts all of group 2. Either it is deployed with the option on, or it
   stays off until its reinstall.
8. **thinkcenter reinstall.** Reinstall it with the automatic secure boot and
   TPM flow, a btrfs root and a disko data disk named `data`. Remove
   `homelab.dataDisk.legacyLayout`. It rejoins as the standby, and the sync
   runs in both directions from then on. The two alertmanagers cluster and
   fluent-bit ships to both lokis.
9. **One relay per host.** Each host's relay announces its own address,
   management lists both, and the relay moves from group 2 to group 1. The
   relay's port drops out of the reject unit.

## Open questions

- Whether a host whose peer is unreachable may start group 2 at boot at all,
  or waits for the peer or the operator, like corosync's `wait_for_all`.
- A network-attached zigbee coordinator would remove the manual dongle move.
- Whether grafana moves to a local SQLite database to join group 1.
- Service IPs sit on the dummy interface as `/24`. A host with any service IP
  then treats the whole range as local and cannot reach a service that runs
  only on the other host. Group 1 on m75q needs `/32` first.

## Sources

Checked against the deployed versions in November 2026.

- Netbird routing peers: https://docs.netbird.io/manage/networks/how-routing-peers-work
- Netbird HA: https://docs.netbird.io/selfhosted/maintenance/scaling/high-availability
- Netbird external relays: https://docs.netbird.io/selfhosted/maintenance/scaling/set-up-external-relays
- Netbird networks API: https://docs.netbird.io/api/resources/networks
- PostgreSQL warm standby and failover: https://www.postgresql.org/docs/16/warm-standby.html
- PostgreSQL hot standby: https://www.postgresql.org/docs/16/hot-standby.html
- pg_rewind: https://www.postgresql.org/docs/16/app-pgrewind.html
- Patroni multi-site: https://patroni.readthedocs.io/en/latest/ha_multi_dc.html
- nginx upstream: https://nginx.org/en/docs/http/ngx_http_upstream_module.html
- nginx stream upstream: https://nginx.org/en/docs/stream/ngx_stream_upstream_module.html
- Alertmanager HA: https://prometheus.io/docs/alerting/latest/high_availability/
- Fluent Bit retries: https://docs.fluentbit.io/manual/administration/scheduling-and-retries
- Let's Encrypt rate limits: https://letsencrypt.org/docs/rate-limits/
- immich remote machine learning: https://docs.immich.app/guides/remote-machine-learning/
- grafana HA: https://grafana.com/docs/grafana/latest/setup-grafana/set-up-for-high-availability/
- vaultwarden backup: https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault
- Dex storage: https://dexidp.io/docs/configuration/storage/
- ntfy clustering: https://docs.ntfy.sh/config/
- zigbee2mqtt FAQ: https://www.zigbee2mqtt.io/guide/faq/
- votequorum: https://manpages.debian.org/testing/corosync/votequorum.5.en.html
