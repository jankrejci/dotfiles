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
| 1. m75q tunnel and backup upstreams on vpsfree | open |
| 2. Shared server configuration and `homelab-active.target` | open |
| 3. PostgreSQL streaming replication | open |
| 4. File and bulk data sync | open |
| 5. Promote command | open |
| 6. First switchover to m75q | open |
| 7. thinkcenter reinstalled as the btrfs standby | open |

## Goal

- Either machine can fail completely, and the other one runs the whole homelab.
- Both hosts carry the same service configuration. Which one is active is
  runtime state, not configuration.
- Traffic switches on its own. Data that can be lost or diverge only changes
  hands through one deliberate command.
- thinkcenter stays untouched until m75q has taken over. Every change before
  the switchover has to leave thinkcenter's generated system unchanged.

Both machines sit in the same home, so this covers the loss of a machine, not
of the site. The borg backups on vpsfree stay the answer to that.

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

Two machines also cannot tell a dead peer from a cut link, since there is no
third vote. The design therefore switches traffic automatically and leaves the
ownership of the data to a manual promote.

## Architecture

### Entry points, switched automatically

- **VPN services on `192.168.91.0/24`.** One Netbird Network with both hosts
  as routing peers, added individually so each has its own metric. The lowest
  metric is the active host. Clients prefer it whenever it is connected and
  fail over at once when it goes offline. Needs client v0.82.0 or later. See
  https://docs.netbird.io/manage/networks/how-routing-peers-work
- **Public entry and the Netbird control plane on vpsfree.** m75q gets its own
  WireGuard tunnel to vpsfree. vpsfree's nginx lists the active host as the
  upstream and the other one as `backup`, both for the HTTP proxy and for the
  stream proxy that carries the relay and STUN.
- **Netbird signal** already runs on vpsfree, so peers that know each other
  can still connect while the management server is down.

Every switch resets open TCP connections through the route, because
masquerade is on. Planned switchovers therefore run at night.

### Group 1: active-active

These run on both hosts all the time. They hold no state that matters, so
whichever host the traffic reaches serves them.

| Service | Why it can run twice |
|---------|----------------------|
| prometheus, blackbox-exporter | each instance scrapes every target on its own |
| alertmanager | clustered so the two instances deduplicate notifications |
| grafana | dashboards are provisioned from the repo, its database follows PostgreSQL |
| loki | logs land on the active host, gaps on the other are accepted |
| dashboard, healthCheck, nginx, acme | no state, both renew the same wildcard certificate |
| tunnel | the backup upstream on vpsfree needs it up on both |

Monitoring therefore survives the loss of either host, and shows the outage.

### Group 2: active-standby

These run only on the active host, under `homelab-active.target`. The
standby keeps them stopped and receives their state.

- Netbird management and relay, Dex, sso-proxy
- vaultwarden, immich with its machine learning and redis, immich-public-proxy,
  memos, jellyfin
- home-assistant, mosquitto, zigbee2mqtt
- prusa-obico, printer
- borg backups, so two hosts never write to the same repositories and the
  standby never archives a stale copy

While the standby is not promoted, its nginx answers group 2 with a page that
says so, rather than with stale data.

### State replication, active to standby

| State | Transport | Loss on takeover |
|-------|-----------|------------------|
| PostgreSQL: vaultwarden, immich, Netbird management, Dex, memos, home-assistant, grafana | streaming replication, the standby is a read-only hot standby | seconds at most |
| Files in `/var/lib`: home-assistant `.storage`, zigbee2mqtt database, vaultwarden keys and attachments, jellyfin SQLite, ntfy users, mosquitto | periodic sync | up to the sync interval |
| Bulk data under `/mnt/data`: immich media, jellyfin media, borg repositories | periodic sync | up to the sync interval |
| Secrets | the same agenix secrets, rekeyed for both hosts | none |

The standby pulls. The source accepts the sync key only through a forced
read-only command such as `rrsync -ro`, with root logins limited to forced
commands, so a compromised standby can read but not change the active host.
The receiving side snapshots after every sync, so a deletion on the source can
be rolled back.

File state copied while services run is not guaranteed consistent. Once both
hosts are on btrfs, snapshots on the source and `btrfs send` replace rsync and
make every copy a point in time. Until thinkcenter is reinstalled, its side
stays rsync.

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
4. Starts `homelab-active.target`.
5. Swaps the Netbird router metrics through the API, so every client prefers
   the new active host. The management server runs again by then. The API
   token is already an agenix secret.
6. Swaps the primary and `backup` upstreams on vpsfree.

### The old active host returns

At boot a host starts group 2 only if it is marked active and the other host
is not reachable as active. A returning thinkcenter therefore sees m75q
active, starts group 1 only, and rejoins PostgreSQL as a replica of m75q. The
swapped metrics keep clients on m75q. Switching back later is the same promote
command in the other direction, run at night.

This protects against a host coming back after an outage. It does not protect
against both hosts running while unable to see each other, which two machines
alone cannot resolve.

## Implementation steps

Each step deploys without touching thinkcenter's services, except step 6.

1. **Tunnel and upstreams.** m75q joins the vpsfree WireGuard tunnel with its
   own address. vpsfree's nginx gets m75q as the `backup` upstream for
   management, relay and STUN.
2. **Shared configuration.** thinkcenter's `homelab` block in
   `flake/hosts.nix` becomes one server definition that both hosts use. Group
   2 services move under `homelab-active.target`. Service user IDs are pinned.
   thinkcenter's generated system stays as it is, compared with the git
   revision pinned.
3. **PostgreSQL replication.** m75q becomes a hot standby of thinkcenter.
4. **File and bulk sync.** The restricted pull channel, a timer on the
   standby, and snapshots on the receiving side.
5. **Promote command.** The steps above as one script, with the metric swap
   and the vpsfree upstream swap.
6. **First switchover.** At night: promote m75q, move the zigbee dongle and
   the printer, check every service.
7. **thinkcenter reinstall.** Reinstall it with the automatic secure boot and
   TPM flow, a btrfs root and a disko data disk named `data`. Remove
   `homelab.dataDisk.legacyLayout`. It rejoins as the standby, and the sync
   runs in both directions from then on.

## Open questions

- How the hosts agree on who is active at boot: a marker file plus a check of
  the other host is the current idea.
- A network-attached zigbee coordinator would remove the manual dongle move.
- loki could receive logs on both hosts instead of accepting gaps.
