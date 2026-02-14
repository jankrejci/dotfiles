# Self-Hosting Netbird VPN

## Goal

Replace Netbird cloud with self-hosted infrastructure. Management and data stay
on thinkcenter. VPSFree acts as the public gateway for clients that haven't
joined the mesh yet.

## Architecture

```
Internet clients
      │
      ▼
┌─────────────────────────────────────────┐
│  vpsfree (public gate)                  │
│  DNS: api.krejci.io → public IP         │
│                                         │
│  nginx reverse proxy (:443)             │
│    /api/*                ──→ thinkcenter management (via WG tunnel)
│    /management.Mgmt.*/   ──→ thinkcenter management (via WG tunnel)
│    /signalexchange.*/    ──→ localhost signal (:8012)
│                                         │
│  signal server           (:8012)        │
│  relay + embedded STUN   (:33080/UDP 3478)
│                                         │
│  WG tunnel: 192.168.99.2 ↔ 192.168.99.1│
└─────────────────────────────────────────┘
          │
   existing WG backup tunnel (port 51821)
          │
┌─────────────────────────────────────────┐
│  thinkcenter (internal)                 │
│                                         │
│  management server       (:8011)        │
│    - PostgreSQL backend                 │
│    - OIDC via external Dex              │
│    - state: /var/lib/netbird-mgmt       │
│                                         │
│  dashboard               (service IP)   │
│    - static files served by nginx       │
│    - API calls → https://api.krejci.io  │
│    - VPN-only access                    │
│                                         │
│  nginx (:443 on WG IP 192.168.99.1)    │
│    - proxies management for vpsfree     │
│    - uses existing wildcard cert        │
│                                         │
│  Dex: add netbird OIDC client           │
└─────────────────────────────────────────┘
```

## Domains

| Domain | DNS target | Purpose |
|--------|-----------|---------|
| `api.krejci.io` | vpsfree public IP | Management API + signal (public, mimics api.netbird.io for mobile app) |
| `netbird.krejci.io` | thinkcenter service IP | Dashboard admin UI (VPN-only) |

Clients configure `api.krejci.io` as their management URL. Mobile apps treat it
like `api.netbird.io`. The management server tells clients where signal and relay
are via its config, both pointing to vpsfree.

## Authentication

### External Dex Integration

Netbird v0.62+ embeds its own Dex instance for local password auth. This cannot
be disabled. However, the management server accepts any OIDC provider via the
`oidcConfigEndpoint` setting.

Our existing Dex at `dex.krejci.io` will be the primary identity provider:
- Google OAuth SSO for regular login
- Local password fallback
- Single identity across all homelab services including Netbird

The embedded Dex runs but is not exposed to users. It only serves as internal
plumbing for the management server's token validation.

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

The management server's `PKCEAuthorizationFlow` and `DeviceAuthorizationFlow`
must also point to our Dex endpoints for CLI and mobile app login.

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

## NixOS Module Status

Nixpkgs (version 0.60.2) provides:

| Component | NixOS module | Package | Status |
|-----------|-------------|---------|--------|
| Management | `services.netbird.server.management` | `netbird-management` | Usable, supports secrets via `_secret` pattern |
| Signal | `services.netbird.server.signal` | `netbird-signal` | Usable, simple gRPC server |
| Dashboard | `services.netbird.server.dashboard` | `netbird-dashboard` | Usable, static file builder with env templating |
| Relay | **None** | `netbird-relay` | Package exists, no NixOS module. Need custom systemd service. |
| Coturn | `services.netbird.server.coturn` | `coturn` | Legacy, replaced by relay with embedded STUN |

### Approach

Use NixOS modules for management, signal, and dashboard. Write a custom systemd
service for relay. Skip coturn entirely since relay includes embedded STUN.

## Implementation Plan

### Phase 1: Thinkcenter - Management Server

New file: `homelab/netbird-server.nix`

1. Create homelab module with `homelab.netbird-server.enable` option
2. Configure management server:
   - NixOS module `services.netbird.server.management`
   - PostgreSQL backend
   - OIDC endpoint pointing to `dex.krejci.io`
   - DNS domain `nb.krejci.io` for peer resolution (matches current `peerDomain`)
   - Single account mode domain
   - DataStoreEncryptionKey via agenix secret
3. Configure dashboard:
   - NixOS module `services.netbird.server.dashboard`
   - Served on service IP (e.g., `192.168.91.9`) via nginx, VPN-only
   - AUTH_AUTHORITY = `https://dex.krejci.io`
   - NETBIRD_MGMT_API_ENDPOINT = `https://api.krejci.io`
4. Configure nginx on WG tunnel interface:
   - Listen on `192.168.99.1:443` for `api.krejci.io`
   - Proxy `/api/*` to management localhost:8011
   - gRPC proxy `/management.ManagementService/*` to localhost:8011
   - Uses existing wildcard `*.krejci.io` ACME cert
5. Add Dex client for netbird in `homelab/dex.nix`
6. Create agenix secrets:
   - `dex-netbird-secret.age` (Dex client secret)
   - `netbird-datastore-key.age` (management encryption key)
7. Enable in `flake/hosts.nix` thinkcenter config
8. Firewall: allow port 8011 on WG tunnel interface only

### Phase 2: VPSFree - Public Gateway

New file: `homelab/netbird-signal.nix` (or extend vpsfree host config)

1. Configure signal server:
   - NixOS module `services.netbird.server.signal`
   - Listen on localhost:8012
2. Configure relay service (custom systemd unit):
   - Package: `netbird-relay`
   - Listen port: 33080 (DERP relay)
   - Embedded STUN on UDP 3478
   - TLS via existing ACME cert
3. Configure nginx at `api.krejci.io:443`:
   - `/api/*` → proxy_pass to `http://192.168.99.1:8011` (thinkcenter via WG)
   - `/management.ManagementService/*` → grpc_pass to `192.168.99.1:8011`
   - `/signalexchange.SignalExchange/*` → grpc_pass to localhost:8012
4. DNS: Add A record `api.krejci.io` → vpsfree public IP (in Cloudflare)
5. Firewall: allow TCP 443, UDP 3478 on public interface
6. TLS: Use ACME cert (vpsfree already has ACME configured)

### Phase 3: Dex Integration

1. Add netbird static client to `homelab/dex.nix`
2. Generate client secret, encrypt with agenix
3. Verify OIDC discovery endpoint serves required claims (sub, email, name)
4. Test PKCE flow for CLI/mobile and device authorization flow

### Phase 4: Client Module Updates

Modify `modules/netbird-homelab.nix` and `modules/netbird-user.nix`:

1. Add configurable management URL (default: `https://api.krejci.io`)
2. Keep existing setup key enrollment logic
3. Update client config to point to self-hosted management
4. Signal and relay URLs come from management server automatically

### Phase 5: Testing

1. Deploy thinkcenter and vpsfree configs (still using cloud Netbird for access)
2. Verify management API is reachable at `https://api.krejci.io/api/`
3. Verify signal connects at `https://api.krejci.io`
4. Verify STUN responds on vpsfree UDP 3478
5. Create test setup key via self-hosted dashboard
6. Enroll one sacrificial peer (e.g., rpi4) against self-hosted management
7. Verify peer appears in dashboard, can reach other self-hosted peers

### Phase 6: Migration (Big-Bang Cutover)

Gradual migration is NOT possible. Each peer connects to exactly one management
server. Peers on different servers cannot communicate. No mesh bridging exists.
See: https://github.com/netbirdio/netbird/issues/446

**Preparation:**
1. Document all groups, policies, routes from Netbird cloud dashboard
2. Recreate groups and policies on self-hosted dashboard
3. Generate setup keys for all server/RPi hosts
4. Prepare deployment scripts

**Cutover (maintenance window):**
1. Deploy client config change to all hosts (management URL → api.krejci.io)
2. Server hosts: automatic re-enrollment via setup keys
3. Desktop hosts: users re-authenticate via tray UI
4. Verify mesh connectivity between all peers
5. Update DNS routes and access policies as needed

**Rollback plan:**
- Keep Netbird cloud account active for 30 days
- If migration fails: revert management URL, re-enroll against cloud
- Setup keys for cloud re-enrollment should be pre-generated

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| NixOS module immaturity | Build/runtime failures | Pin nixpkgs version, test thoroughly before migration |
| No relay NixOS module | Manual service config | Write minimal systemd unit, package is available |
| WG tunnel single point of failure | Management unreachable | Clients cache config, short outage tolerable. Fix WG tunnel. |
| Peer IDs change on re-enrollment | Groups/policies break | Recreate policies before migration, automate via API |
| OIDC claim mismatch | Auth failures | Test Dex token claims include `name` (required by Netbird) |
| Migration downtime | All peers lose mesh access | Schedule maintenance window, pre-stage everything |
| Embedded Dex conflict behind reverse proxy | Auth deadlock | Known issue netbirdio/netbird#5084, test carefully |
| VPSFree LXC constraints | Relay/STUN issues | All components are userspace Go binaries, no kernel deps |

## File Changes Summary

**New files:**
- `homelab/netbird-server.nix` - management + dashboard module for thinkcenter
- `homelab/netbird-signal.nix` - signal + relay module for vpsfree
- `secrets/dex-netbird-secret.age` - Dex client secret
- `secrets/netbird-datastore-key.age` - management encryption key

**Modified files:**
- `homelab/default.nix` - import new modules
- `homelab/dex.nix` - add netbird static client
- `flake/hosts.nix` - enable netbird-server on thinkcenter, netbird-signal on vpsfree
- `modules/netbird-homelab.nix` - configurable management URL
- `modules/netbird-user.nix` - configurable management URL

## Open Questions

1. **Relay configuration**: The netbird-relay binary's exact flags and env vars
   need investigation. No NixOS module exists, documentation is sparse.
2. **Embedded Dex conflict**: Issue #5084 reports deadlocks when running behind
   external reverse proxy. May need workaround or version pinning.
3. **PKCE flow for mobile**: The mobile app uses device authorization flow. Need
   to verify Dex supports this or if the management server handles it internally.
4. **Version compatibility**: Client v0.60.2 vs self-hosted server v0.60.2 should
   match. Verify no breaking changes between versions.
5. **Dashboard access during setup**: During initial configuration, dashboard is
   VPN-only. Admin accesses via old cloud mesh. After migration, via new mesh.
   Verify this bootstrap path works.
