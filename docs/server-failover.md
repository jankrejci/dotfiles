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
| 1. m75q joins the vpsfree tunnel | open |
| 2. Netbird relay moves to vpsfree | open |
| 3. Shared server configuration and `homelab-active.target` | open |
| 4. vpsfree upstreams list both hosts | open |
| 5. PostgreSQL streaming replication | open |
| 6. File and bulk data sync | open |
| 7. Promote command | open |
| 8. First switchover to m75q | open |
| 9. thinkcenter reinstalled as the btrfs standby | open |

## Goal

- Either machine can fail completely, and the other one runs the whole homelab.
- Both hosts carry the same service configuration. Which one is active is
  runtime state, not configuration.
- Traffic switches on its own. Data that can be lost or diverge only changes
  hands through one deliberate command.
- thinkcenter stays untouched until m75q has taken over. Every change before
  the switchover has to leave thinkcenter's generated system unchanged. Step 2
  is the one deliberate exception, because it takes the relay out of the
  failover problem altogether.

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
| alertmanager | the two instances form a gossip cluster and deduplicate notifications, each prometheus sends to both |
| loki | today fluent-bit ships only to the local loki, so each loki holds only its own host's logs. Shipping to both lokis gives each a full copy |
| immich machine learning | stateless. immich accepts a list of machine learning URLs and falls back to the next one, which needs checking against the deployed version |
| dashboard, healthCheck, nginx, acme | no state. Both hosts and vpsfree renew the same wildcard certificate, far below the Let's Encrypt duplicate limit |
| tunnel | the vpsfree upstreams need it up on both |

Monitoring therefore survives the loss of either host, and shows the outage.

### Single writer on PostgreSQL

vaultwarden, immich, memos, Netbird management, Dex, home-assistant's recorder
and grafana all keep their state in PostgreSQL. None of them can run on the
standby:

- A hot standby is read-only, and every one of them writes at startup through
  migrations or on every login.
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
would move to group 1 and lose only preferences and annotations made in the UI.

### Single writer on local files

jellyfin with its SQLite library, ntfy with its user database, prusa-obico,
mosquitto's persistence and vaultwarden's keys and attachments live in
`/var/lib`. These have no replication protocol, so the standby receives
periodic copies and the services stay stopped there.

### Stateless, but tied to a single writer

sso-proxy and immich-public-proxy hold no state, yet they only forward to Dex
and immich. They follow their backends into group 2.

### Pinned to hardware

zigbee2mqtt owns the USB coordinator, and home-assistant and mosquitto are
only useful together with it. The printer is attached to one host too. These
need hands during a takeover. A network-attached zigbee coordinator would
remove that, but only one zigbee2mqtt may connect to it at a time, so it still
belongs to group 2.

### Off both hosts

- **Netbird signal** already runs on vpsfree.
- **Netbird relay** moves there in step 2. It is stateless, needs only the
  wildcard certificate that vpsfree already renews and the relay secret, and
  only ever sees WireGuard ciphertext. Relayed traffic today goes from
  vpsfree over the tunnel to thinkcenter and back again, so moving it also
  removes that hairpin.
- **STUN** comes from Google's public server, which management advertises.
  The STUN stream proxy on vpsfree forwards to a port nothing listens on and
  can be removed.

### Groups

- **Group 1** runs on both hosts: the services under "Independent on both
  hosts".
- **Group 2** runs only on the active host, under `homelab-active.target`:
  Netbird management, Dex, sso-proxy, vaultwarden, immich with redis,
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
of the data to a manual promote.

## Architecture

### Entry points, switched automatically

- **VPN services on `192.168.91.0/24`.** One Netbird Network with both hosts
  as routing peers, added individually so each has its own metric. The lowest
  metric is the active host. Clients prefer it whenever it is connected and
  fail over at once when it goes offline. Needs client v0.82.0 or later. See
  https://docs.netbird.io/manage/networks/how-routing-peers-work
- **Public entry on vpsfree.** m75q gets its own WireGuard tunnel to vpsfree.
  What still goes through the tunnel is TCP: the management API and gRPC, and
  the SNI passthrough for `share.` and `auth.`. vpsfree lists both hosts as
  equal upstream servers. The standby rejects these ports on `wg0` with a TCP
  reset through a unit that conflicts with `homelab-active.target`, so nginx
  fails over to the active host at once. A dead host does not answer at all,
  so nginx needs a connect timeout of a few seconds and `max_fails=1` to skip
  it quickly. The promote never has to touch vpsfree.
- **Netbird signal and relay** run on vpsfree, so peers that know each other
  can still connect while the management server is down.

The standby keeps SSH open on `wg0`, so it stays reachable through vpsfree.

Every switch resets open TCP connections through the route, because
masquerade is on. Planned switchovers therefore run at night.

### State replication, active to standby

| State | Transport | Loss on takeover |
|-------|-----------|------------------|
| PostgreSQL: vaultwarden, immich, Netbird management, Dex, memos, home-assistant, grafana | streaming replication, the standby is a read-only hot standby | seconds at most |
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

### Service users

Copied files keep their numeric owners. The service users get thinkcenter's
existing user and group IDs pinned in the shared configuration, so a file
means the same on both hosts. No new IDs are introduced.

## Procedures

### Unplanned failure of the active host

1. Netbird and vpsfree move traffic to the standby on their own.
2. Group 1 keeps working. Group 2 shows the standby page.
3. Reach the standby over Netbird, which signal on vpsfree keeps working, or
   over the LAN, or through vpsfree and its WireGuard tunnel.
4. Run the promote command on the standby.
5. Move the zigbee dongle and the printer to it.

### Promote

The one command does, in order:

1. Stops group 2 on the old active host if it is reachable.
2. Marks the new host active.
3. Runs `pg_promote`.
4. Starts `homelab-active.target`, which also stops the `wg0` reject unit.
5. Swaps the Netbird router metrics through the API, so every client prefers
   the new active host. The management server runs again by then. The API
   token is already an agenix secret.

### The old active host returns

At boot a host starts group 2 only if it is marked active and the other host
is not reachable as active. A returning thinkcenter therefore sees m75q
active, starts group 1 only, and rejoins PostgreSQL as a replica of m75q. The
swapped metrics keep clients on m75q, and its reject unit keeps vpsfree on
m75q. Switching back later is the same promote command in the other
direction, run at night.

This protects against a host coming back after an outage. It does not protect
against both hosts running while unable to see each other. Only a quorum
could resolve that, and the reasons against one are above.

## Implementation steps

Each step deploys without touching thinkcenter's services, except steps 2
and 8.

1. **m75q joins the tunnel.** Generate its WireGuard key on the host, commit
   the public key, give it its own tunnel address and add it to vpsfree's
   peers. vpsfree's tunnel health check pings every peer, so it reports
   m75q whenever m75q is off.
2. **Relay to vpsfree.** Run netbird-relay on vpsfree with the relay secret,
   point management's relay address at it, drop the relay from thinkcenter
   and the relay and STUN stream proxies from vpsfree.
3. **Shared configuration.** thinkcenter's `homelab` block in
   `flake/hosts.nix` becomes one server definition that both hosts use. Group
   2 services move under `homelab-active.target`, and the `wg0` reject unit
   conflicts with it. Service user IDs are pinned. Alertmanager clusters and
   fluent-bit ships to both lokis. thinkcenter's generated system stays as it
   is, compared with the git revision pinned.
4. **vpsfree upstreams.** Management API and gRPC go through one upstream
   with both hosts, and the SNI passthrough in `tunnel.nix` stops taking only
   the first peer. This comes after step 3, because before the reject unit
   exists m75q drops these ports instead of rejecting them.
5. **PostgreSQL replication.** m75q becomes a hot standby of thinkcenter.
6. **File and bulk sync.** The restricted pull channel, a timer on the
   standby, and snapshots on the receiving side.
7. **Promote command.** The steps above as one script, with the metric swap.
8. **First switchover.** At night: promote m75q, move the zigbee dongle and
   the printer, check every service.
9. **thinkcenter reinstall.** Reinstall it with the automatic secure boot and
   TPM flow, a btrfs root and a disko data disk named `data`. Remove
   `homelab.dataDisk.legacyLayout`. It rejoins as the standby, and the sync
   runs in both directions from then on.

## Open questions

- How the hosts agree on who is active at boot: a marker file plus a check of
  the other host is the current idea.
- A network-attached zigbee coordinator would remove the manual dongle move.
- Whether grafana moves to a local SQLite database to join group 1.
