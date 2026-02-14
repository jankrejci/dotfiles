# Self-Hosting Netbird VPN

## Goal

Replace Netbird cloud with self-hosted infrastructure. Management and data stay
on thinkcenter. VPSFree acts as the public gateway for clients that haven't
joined the mesh yet.

## Architecture

```
Internet clients (mobile app, CLI, desktop tray, new peers)
      │
      ▼
┌──────────────────────────────────────────────────────────────┐
│  vpsfree (public gate)                                       │
│  DNS: api.krejci.io → vpsfree public IP (Cloudflare A record)│
│                                                              │
│  nginx reverse proxy (:443)                                  │
│    /api/*                ──→ management REST API              │
│                              (thinkcenter via WG tunnel)     │
│    /management.Mgmt.*/   ──→ management gRPC for peer sync   │
│                              (thinkcenter via WG tunnel)     │
│    /signalexchange.*/    ──→ signal gRPC (localhost :8012)   │
│    /relay*               ──→ relay DERP (localhost :33080)   │
│                                                              │
│  signal server (:8012)                                       │
│    Coordinates peer-to-peer connection establishment.        │
│    When two peers want to talk, signal brokers the initial   │
│    handshake so they can open a direct WireGuard tunnel.     │
│    Stateless, no sensitive data.                             │
│                                                              │
│  relay + embedded STUN (:33080 / UDP 3478)                   │
│    Relay: fallback path when direct peer-to-peer fails due   │
│    to strict NAT or firewalls. Traffic routes through relay  │
│    instead of directly. Uses DERP protocol over TLS.         │
│    STUN: helps peers discover their public IP and port for   │
│    NAT traversal. Standard UDP protocol on port 3478.        │
│    Contains: relay auth secret, TLS cert. No mesh data.      │
│                                                              │
│  WG tunnel: 192.168.99.2 ↔ 192.168.99.1                     │
└──────────────────────────────────────────────────────────────┘
          │
   existing WG backup tunnel (port 51821, independent of Netbird)
          │
┌──────────────────────────────────────────────────────────────┐
│  thinkcenter (internal, VPN-only)                            │
│                                                              │
│  management server (:8011)                                   │
│    The control plane. Stores peer configs, groups, policies, │
│    routes, DNS settings. Every client (mobile, CLI, desktop) │
│    talks to management API to get its mesh configuration.    │
│    - PostgreSQL backend                                      │
│    - OIDC via external Dex                                   │
│    - state: /var/lib/netbird-mgmt                            │
│                                                              │
│  dashboard (service IP, e.g. 192.168.91.9)                   │
│    Admin web UI. Static files served by nginx. Makes API     │
│    calls to management at https://api.krejci.io. VPN-only,   │
│    NOT exposed to the internet. Accessed by admin via mesh.  │
│                                                              │
│  nginx (:443 on WG IP 192.168.99.1)                          │
│    Proxies management API for vpsfree over WG tunnel.        │
│    Uses existing wildcard *.krejci.io ACME cert.             │
│                                                              │
│  Dex: add netbird OIDC client                                │
│  PostgreSQL: add netbird database                            │
└──────────────────────────────────────────────────────────────┘
```

### Security Note: VPSFree

VPSFree is LXC-based with a shared kernel. The host operator could theoretically
access container memory. Components on vpsfree handle:
- Signal: stateless, no secrets
- Relay: auth secret (prevents unauthorized relay use) and TLS cert/key
- Nginx: TLS cert/key, proxy config

No mesh traffic is readable since WireGuard provides end-to-end encryption
between peers. The relay auth secret limits who can use the relay but does not
expose peer communications. This is comparable to what vpsfree already handles
(ACME certs, WG tunnel keys, netbird client credentials).

## Domains

| Domain | DNS target | Purpose |
|--------|-----------|---------|
| `api.krejci.io` | vpsfree public IP | Management API + signal + relay (public, mimics api.netbird.io) |
| `netbird.krejci.io` | thinkcenter service IP | Dashboard admin UI (VPN-only) |

Both DNS records managed in Cloudflare:
- `api.krejci.io`: A record → vpsfree public IP (new record, must be created)
- `netbird.krejci.io`: handled by local /etc/hosts on thinkcenter (same as other
  services, no public DNS record needed)

Clients configure `api.krejci.io` as their management URL. Mobile apps treat it
like `api.netbird.io` so users only enter `api.krejci.io` with no port number.
The management server tells clients where signal and relay are via its config,
both pointing to vpsfree on standard port 443.

### Port Strategy

Target all public traffic through port 443 to minimize client configuration:
- Management API, signal gRPC, and relay DERP all multiplexed through nginx on
  port 443 with path-based routing. This matches how Netbird cloud works.
- STUN on UDP 3478 is the only additional port. This is the standard STUN port
  that clients expect, no configuration needed.
- Investigation needed: verify nginx can proxy DERP protocol (HTTP-upgrade based,
  similar to WebSocket). If not, relay needs its own port and clients will need
  `rels://api.krejci.io:PORT` in their config, distributed automatically by the
  management server.

## Authentication

### External Dex Integration

Netbird v0.62+ embeds its own Dex instance for local password auth. This cannot
be disabled. However, the management server accepts any OIDC provider via the
`oidcConfigEndpoint` setting.

Our existing Dex at `dex.krejci.io` will be the primary identity provider:
- Google OAuth SSO for regular login
- Local password fallback (jkr user with bcrypt hash)
- Single identity across all homelab services including Netbird

The embedded Dex runs but is not exposed to users. It only serves as internal
plumbing for the management server's token validation.

### Bootstrap Authentication

During initial setup, before any peer has joined the new mesh:
1. Admin connects framework to new mesh (first peer enrollment)
2. Framework reaches thinkcenter service IPs via new mesh
3. Admin logs into dashboard using Dex **local password** for jkr
4. No Google OAuth dependency needed for bootstrap
5. Once mesh is stable, Google OAuth works as the primary login method

If the new mesh has issues and the dashboard is unreachable, the management
server's embedded Dex provides a last-resort local auth fallback accessible from
thinkcenter console.

### Configuration

Add netbird as a Dex static client in `homelab/dex.nix`:
```nix
{
  id = "netbird";
  name = "Netbird";
  redirectURIs = [
    "https://netbird.krejci.io/nb-auth"
    "https://netbird.krejci.io/nb-silent-auth"
  ];
  secretFile = config.age.secrets.dex-netbird-secret.path;
}
```

Management server OIDC config:
```nix
oidcConfigEndpoint = "https://dex.krejci.io/.well-known/openid-configuration";
```

Dashboard settings:
```nix
AUTH_AUTHORITY = "https://dex.krejci.io";
AUTH_CLIENT_ID = "netbird";
```

### Mobile App and CLI Auth

The management server's `PKCEAuthorizationFlow` and `DeviceAuthorizationFlow`
must point to Dex endpoints for CLI and mobile app login. Dex supports the
authorization code flow with PKCE which modern mobile apps use. The device
authorization flow (for headless CLI login) uses Dex endpoints at `/device/code`
and `/device/token`. This needs explicit testing before migration since not all
Dex versions handle device authorization flow identically. If device authorization
is unsupported, CLI falls back to PKCE with local redirect on port 53000.

## Database

PostgreSQL on thinkcenter, same instance used by Dex, Grafana, Immich, Memos.

```nix
services.postgresql = {
  ensureDatabases = ["netbird"];
  ensureUsers = [{
    name = "netbird";
    ensureDBOwnership = true;
  }];
};
```

Management server config:
```nix
settings.StoreConfig = {
  Engine = "postgres";
  Connection = "postgresql:///netbird?host=/run/postgresql";
};
```

## Packages and NixOS Modules

Use nixpkgs-unstable (0.64.6) for all Netbird components via `pkgs.unstable.*`.
Stable nixpkgs has 0.60.2 which predates the built-in auth feature (v0.62).
The NixOS modules are identical between stable and unstable.

| Component | NixOS module | Package | Status |
|-----------|-------------|---------|--------|
| Management | `services.netbird.server.management` | `netbird-management` | Usable, supports secrets via `_secret` pattern |
| Signal | `services.netbird.server.signal` | `netbird-signal` | Usable, simple gRPC server |
| Dashboard | `services.netbird.server.dashboard` | `netbird-dashboard` | Usable, static file builder with env templating |
| Relay | **No NixOS module** | `netbird-relay` | Package exists. Custom systemd service needed. |
| Coturn | `services.netbird.server.coturn` | `coturn` | Legacy, skip. Relay has embedded STUN. |

Override packages in modules to use unstable:
```nix
services.netbird.server.management.package = pkgs.unstable.netbird-management;
services.netbird.server.signal.package = pkgs.unstable.netbird-signal;
services.netbird.server.dashboard.package = pkgs.unstable.netbird-dashboard;
```

### Relay Service Configuration

No NixOS module exists. Write a custom systemd service using the relay binary
from `pkgs.unstable.netbird-relay`. Key flags:

```
netbird-relay
  --listen-address :443             # listen on standard HTTPS port
  --exposed-address api.krejci.io   # public address distributed to peers via management
  --enable-stun                     # run embedded STUN server alongside relay
  --stun-ports 3478                 # STUN on standard UDP port
  --tls-cert-file /path/cert.pem    # TLS certificate from ACME
  --tls-key-file /path/key.pem      # TLS private key from ACME
  --auth-secret <secret>            # shared secret between relay and management server
  --log-file console
  --log-level info
```

If relay runs on port 443 directly (handling its own TLS), it conflicts with
nginx. Two options:
1. Run relay on an internal port, proxy through nginx (needs DERP protocol test)
2. Run relay on a separate port (e.g., 33080), distribute via management config

Option 1 is preferred for minimal client configuration. Will test during
implementation.

### Approach

Use NixOS modules for management, signal, and dashboard. Write a custom systemd
service for relay. Skip coturn entirely since relay includes embedded STUN.

## Implementation Plan

### Phase 1: VPSFree - Public Gateway (non-breaking)

New file: `homelab/netbird-gateway.nix`

Module providing the public-facing Netbird components on vpsfree. This is the
entry point for all clients connecting to the mesh. Handles signal coordination,
relay fallback, and proxies management API requests to thinkcenter.

1. Configure signal server:
   - NixOS module `services.netbird.server.signal`
   - Package: `pkgs.unstable.netbird-signal`
   - Listen on localhost:8012
2. Configure relay service (custom systemd unit):
   - Package: `pkgs.unstable.netbird-relay`
   - Embedded STUN on UDP 3478
   - TLS cert/key from ACME
   - Auth secret shared with management server (via agenix)
3. Configure nginx at `api.krejci.io:443`:
   - `/api/*` -> proxy to thinkcenter management via WG tunnel (192.168.99.1)
   - `/management.ManagementService/*` -> gRPC proxy to thinkcenter via WG tunnel
   - `/signalexchange.SignalExchange/*` -> gRPC proxy to localhost:8012
   - Relay: proxied or separate port (determined during implementation)
4. DNS: Create A record `api.krejci.io` -> vpsfree public IP in Cloudflare
5. Firewall: allow TCP 443, UDP 3478 on public interface
6. TLS: Use ACME cert (vpsfree already has ACME configured)

This phase is non-breaking. New services run alongside existing infrastructure
without affecting current Netbird cloud clients.

### Phase 2: Thinkcenter - Management Server (non-breaking)

New file: `homelab/netbird-server.nix`

Module providing the Netbird management server and admin dashboard on
thinkcenter. Stores all mesh configuration, handles authentication, and serves
the admin interface behind VPN.

1. Create homelab module with `homelab.netbird-server.enable` option
2. Configure management server:
   - NixOS module `services.netbird.server.management`
   - Package: `pkgs.unstable.netbird-management`
   - PostgreSQL backend
   - OIDC endpoint pointing to `dex.krejci.io`
   - DNS domain `nb.krejci.io` for peer resolution (matches current `peerDomain`)
   - Single account mode domain
   - DataStoreEncryptionKey via agenix secret
   - Relay auth secret shared with vpsfree relay
3. Configure dashboard:
   - NixOS module `services.netbird.server.dashboard`
   - Package: `pkgs.unstable.netbird-dashboard`
   - Served on service IP (e.g., `192.168.91.9`) via nginx, VPN-only
   - AUTH_AUTHORITY = `https://dex.krejci.io`
   - NETBIRD_MGMT_API_ENDPOINT = `https://api.krejci.io`
4. Configure nginx on WG tunnel interface:
   - Listen on `192.168.99.1:443` for `api.krejci.io`
   - Proxy `/api/*` to management localhost:8011
   - gRPC proxy `/management.ManagementService/*` to localhost:8011
   - Uses existing wildcard `*.krejci.io` ACME cert
5. Firewall: management port 8011 accessible only from localhost and WG tunnel

This phase is non-breaking. Management server runs but no clients connect to it
yet. Existing cloud mesh is unaffected.

### Phase 3: Dex Integration (non-breaking)

1. Add netbird static client to `homelab/dex.nix`
2. Generate client secret, encrypt with agenix
3. Verify OIDC discovery endpoint serves required claims (sub, email, name)
4. Test PKCE flow for CLI/mobile and device authorization flow
5. Create agenix secrets:
   - `dex-netbird-secret.age` (Dex client secret)
   - `netbird-datastore-key.age` (management encryption key)
   - `netbird-relay-secret.age` (relay auth secret, shared with management)

### Phase 4: Client Module Updates (non-breaking, prep only)

Modify `modules/netbird-homelab.nix` and `modules/netbird-user.nix`:

1. Add configurable management URL (default remains cloud for now)
2. Use `pkgs.unstable.netbird` for client (0.64.6 to match server)
3. Keep existing setup key enrollment logic
4. Do NOT change management URL yet. Just prepare the option.
5. Signal and relay URLs come from management server automatically

### Phase 5: Testing

1. Deploy thinkcenter and vpsfree configs (still using cloud Netbird for access)
2. Verify management API is reachable at `https://api.krejci.io/api/`
3. Verify signal connects at `https://api.krejci.io`
4. Verify STUN responds on vpsfree UDP 3478
5. Access self-hosted dashboard via VPN, log in with jkr local password
6. Recreate groups, policies, routes from cloud config reference
   (see `docs/netbird-cloud-config.json`)
7. Create setup keys for server/RPi hosts

### Phase 6: Migration (Rolling Cutover)

Gradual migration is NOT possible at the mesh level. Each peer connects to
exactly one management server. Peers on different servers cannot communicate.
See: https://github.com/netbirdio/netbird/issues/446

However, we can do a rolling cutover with two admin machines on opposite sides:

**Preparation:**
1. Reference config saved in `docs/netbird-cloud-config.json`
2. Recreate all groups, policies, routes on self-hosted dashboard
3. Generate setup keys for all server/RPi hosts
4. Pre-generate cloud re-enrollment setup keys (for rollback)

**Rolling cutover sequence:**

```
Step 1: framework joins new mesh (physically accessible, local password login)
        t14 stays on cloud mesh as deployment bridge
        All servers/RPis still on cloud mesh

Step 2: From framework (new mesh), verify thinkcenter reachable
        Access dashboard, confirm policies are correct

Step 3: From t14 (cloud mesh), deploy to thinkcenter
        Thinkcenter re-enrolls to new mesh via setup key
        framework <-> thinkcenter now communicate via new mesh

Step 4: From t14 (cloud mesh), deploy to remaining servers one by one:
        vpsfree, rpi4, prusa, rak2245
        Each re-enrolls to new mesh
        Verify each comes online in self-hosted dashboard

Step 5: From t14 (cloud mesh), deploy to desktops:
        e470, optiplex
        Users re-authenticate via tray UI

Step 6: Migrate t14 itself (last machine)
        At this point, all other hosts are on new mesh
        If t14 migration fails, all other hosts are still reachable
        from framework via new mesh

Step 7: Verify full mesh connectivity between all peers
```

**Rollback plan:**
- Keep Netbird cloud account active for 30 days
- If migration fails mid-sequence: unaffected hosts still on cloud mesh
- t14 remains on cloud mesh until step 6, providing a fallback deployment path
- Pre-generated cloud setup keys allow re-enrollment back to cloud

## Declarative Configuration Management

### Current State (Manual)

Netbird groups, policies, routes, and DNS settings are managed through the
dashboard UI or REST API. This is the approach for initial deployment.

### Future: Nix-Managed Configuration

The CLAUDE.md notes that declarative API management was prototyped but abandoned
due to peer ID instability. However, peer IDs only affect **peer group
membership**. The following entities are stable and can be managed declaratively:

- **Groups** (by name)
- **ACL policies** (referencing groups by name)
- **Routes** (network CIDR, routing peers by group)
- **DNS nameserver settings**
- **Posture checks**

A Nix module could define the desired state and reconcile it via the management
API on each deployment:

```nix
homelab.netbird-server.config = {
  groups = [
    { name = "servers"; }
    { name = "desktops"; }
    { name = "rpi"; }
  ];
  policies = [
    {
      name = "servers-full-access";
      sources = ["servers"];
      destinations = ["servers"];
      action = "accept";
    }
  ];
};
```

Peer assignment to groups would remain manual or use setup key auto-groups once
Netbird supports that feature. This is a follow-up improvement after the initial
deployment is stable.

## Cloud Configuration Reference

Current Netbird cloud configuration is saved in `docs/netbird-cloud-config.json`
for reference when recreating groups, policies, and routes on the self-hosted
instance. This file was exported via the Netbird REST API. Sensitive values
(setup key strings, API tokens) are redacted.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| NixOS module immaturity | Build/runtime failures | Use unstable 0.64.6, test thoroughly before migration |
| No relay NixOS module | Manual service config | Write minimal systemd unit, relay flags are well-defined |
| WG tunnel single point of failure | Management unreachable | Clients cache config, short outage tolerable. Fix WG tunnel. |
| Peer IDs change on re-enrollment | Groups/policies break | Recreate policies before migration, automate via API |
| OIDC claim mismatch | Auth failures | Test Dex token claims include `name` (required by Netbird) |
| Rolling cutover complexity | Partial mesh during transition | framework + t14 on opposite meshes, always have admin access |
| Embedded Dex reverse proxy conflict | Auth deadlock on startup | Issue #5084 (v0.62.0). In our setup management and proxy are on different hosts (thinkcenter vs vpsfree) so circular dependency should not occur. If management tries to reach itself via public URL, add /etc/hosts entry to resolve api.krejci.io to 127.0.0.1 on thinkcenter. Test during phase 5. |
| PKCE/device auth flow | Mobile app login fails | Test Dex device authorization endpoint before migration. Fallback: PKCE with local redirect on port 53000. |
| VPSFree LXC constraints | Relay/STUN issues | All components are userspace Go binaries, no kernel deps. No sensitive mesh data stored. |
| DERP proxy through nginx | Relay unreachable on port 443 | Test during phase 1. Fallback: relay on separate port, management distributes URL automatically. |

## File Changes Summary

**New files:**
- `homelab/netbird-server.nix` - management + dashboard module for thinkcenter.
  Provides the control plane: stores peer configs, policies, groups, routes in
  PostgreSQL. Serves the admin dashboard on a VPN-only service IP. Handles OIDC
  authentication via external Dex.
- `homelab/netbird-gateway.nix` - signal + relay + nginx proxy module for vpsfree.
  Provides the public-facing entry point: signal for peer connection handshakes,
  relay for fallback traffic, nginx for proxying management API to thinkcenter.
- `docs/netbird-cloud-config.json` - exported cloud configuration reference for
  recreating groups, policies, routes, DNS settings on self-hosted instance.
- `secrets/dex-netbird-secret.age` - Dex client secret for netbird OIDC
- `secrets/netbird-datastore-key.age` - management server encryption key for
  stored peer data
- `secrets/netbird-relay-secret.age` - shared auth secret between relay and
  management, prevents unauthorized relay use

**Modified files:**
- `homelab/default.nix` - import new modules
- `homelab/dex.nix` - add netbird static client
- `flake/hosts.nix` - enable netbird-server on thinkcenter, netbird-gateway on vpsfree
- `modules/netbird-homelab.nix` - configurable management URL
- `modules/netbird-user.nix` - configurable management URL

## Open Questions

1. **DERP proxy through nginx**: Can nginx proxy the DERP relay protocol
   (HTTP-upgrade based)? If yes, all traffic goes through port 443. If not,
   relay needs a separate port. Test during phase 1 implementation.
2. **Embedded Dex startup conflict**: Issue #5084 (v0.62.0) reports deadlocks
   behind reverse proxy. Our split-host architecture likely avoids this since
   management and proxy are on different machines. Verify during phase 5.
3. **Device authorization flow**: Verify Dex supports the device authorization
   endpoint at `/device/code` for headless CLI login. Test before migration.
