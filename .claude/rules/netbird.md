---
paths:
  - "modules/netbird-*.nix"
  - "modules/networking.nix"
  - "homelab/netbird-*.nix"
  - "scripts/reenroll-netbird.nix"
---

# Netbird Architecture

Two-tier VPN setup for different access patterns:

**System client** (`netbird-homelab`, port 51820):
- Setup key enrollment, always running as system service
- For infrastructure: SSH, monitoring, node scraping
- Machine-based policies, no expiration
- Module: `modules/netbird-homelab.nix`
- Used by: servers via headless.nix, RPi via raspberry.nix

**User client** (`netbird-user`, port 51821):
- Runs as systemd user service on desktops
- SSO login via tray UI, user-based policies
- Module: `modules/netbird-user.nix`
- Used by: desktops via desktop.nix
- User must authenticate via tray UI before VPN works

**Server components** (all on thinkcenter):
- Management: control plane with PostgreSQL, port 8011
- Signal: peer connection handshake broker, port 8012
- Relay: fallback traffic path with own TLS, port 33080
- Dashboard: static admin UI, VPN-only access
- Module: `homelab/netbird-server.nix`

**Public proxy** (vpsfree, stateless):
- nginx http: proxies management API, signal gRPC, Dex OIDC on port 443
- nginx stream: relay TLS passthrough on port 33080, STUN UDP on 3478
- All traffic forwarded to thinkcenter via WG backup tunnel
- Module: `homelab/netbird-signal.nix`

**Module structure:**
- `networking.nix` - general networking, no netbird config
- `netbird-homelab.nix` - system client for servers/RPi
- `netbird-user.nix` - user client for desktops

**Limitation:** Cannot run both clients simultaneously due to routing table conflict.
See: https://github.com/netbirdio/netbird/issues/2023

## Declarative Configuration

Declarative Netbird API management was prototyped but abandoned for now. The approach
worked but had a fundamental limitation: peer IDs change on re-enrollment, making
automatic group membership sync impractical. Manual dashboard management is simpler
until Netbird supports stable peer identifiers or setup-key-based group assignment.

Future work: revisit when Netbird adds stable identifiers or setup key groups feature.
