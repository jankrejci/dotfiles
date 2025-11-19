# Netbird Migration

## Status: ✅ COMPLETED
WireGuard removed, HTTPS enabled, domain migrated to krejci.io

## Migration Summary

**From:** Manual WireGuard mesh (192.168.99.0/24) + CoreDNS on vpsfree + HTTP-only services
**To:** Netbird hosted VPN (100.76.0.0/16) + Netbird DNS (*.krejci.io) + HTTPS everywhere

### Key Changes
- VPN: Self-managed WireGuard → Netbird (https://app.netbird.io)
- DNS: CoreDNS on vpsfree → Netbird embedded DNS
- Domain: *.vpn → *.krejci.io
- Security: HTTP → HTTPS (Let's Encrypt wildcard certs, DNS-01 challenge)
- Architecture: Defense-in-depth (services on localhost, nginx TLS termination, firewall on nb-homelab)

### Enrolled Hosts
- vpsfree: 100.76.208.183 (Grafana, public Immich proxy)
- thinkcenter: 100.76.x.x (Immich)
- framework: 100.76.232.215
- t14: 100.76.144.136
- optiplex: 100.76.24.123
- e470, rpi4, prusa: pending enrollment

## Implementation

### Enrollment Process
See: `scripts.nix` (`nixos-install` function)

1. Generate one-off setup key via Netbird API (expires 24h, single use)
2. Store in `/var/lib/netbird-homelab/setup-key` during installation
3. Oneshot service (`netbird-homelab-enroll`) runs on first boot
4. Enrollment succeeds → setup key deleted
5. Service disabled (ConditionPathExists prevents future runs)

### DNS Configuration
Netbird dashboard: Enable embedded DNS on port 53
Requires: `CAP_NET_BIND_SERVICE` capability (see `modules/networking.nix`)

Domain resolution: `hostname.krejci.io` → Netbird IP

### Extra DNS Labels
See: `hosts.nix` (`extraDnsLabels` option), `modules/networking.nix`

Allows service aliases: `extraDnsLabels = ["immich"]` creates `immich.krejci.io` → `thinkcenter.krejci.io`

Requirements:
- Setup key permission: "Allow Extra DNS labels" enabled
- Fresh enrollment required to apply labels
- To modify: delete peer, re-enroll with updated config

### HTTPS Migration
See: `modules/acme.nix`, `modules/grafana.nix`, `modules/immich.nix`

1. Wildcard cert: `*.krejci.io` + `krejci.io` (DNS-01 via Cloudflare)
2. Services: localhost only (127.0.0.1)
3. Nginx: TLS termination, reverse proxy
4. Firewall: nb-homelab interface only

Setup: `nix run .#inject-cloudflare-token <hostname>`

## Lessons Learned

### Multi-Instance Services
Netbird uses instance name in paths: `/var/run/netbird-homelab/sock`
CLI commands need: `--daemon-addr unix:///var/run/netbird-homelab/sock`

### Oneshot Enrollment Service Pattern
- `ConditionPathExists` prevents running without setup key
- `after` + `requires` ensures daemon ready
- `set -euo pipefail` prevents deleting key on failure
- Retry logic handles timing issues
- See `modules/networking.nix` for reference

### vpsAdminOS Containers
Key issues:
- `console.enable = true` required (disabled by `boot.isContainer`)
- Disable `systemd-networkd-wait-online` (vpsAdminOS manages network externally)
- Disable DHCP on ethernet interface
- Manual DNS configuration

See: `modules/vpsadminos.nix`, `hosts/vpsfree/configuration.nix`

### VPN IP Stability
Netbird assigns new IPs on re-enrollment. Don't hardcode IPs in nginx listen - use access control:
```nix
listenAddresses = ["0.0.0.0"];
extraConfig = "allow 100.76.0.0/16; deny all;";
```

## Troubleshooting

### No Console Login (vpsAdminOS)
Check: `modules/vpsadminos.nix` has `console.enable = true`

### Boot Hangs at "Wait for Network"
vpsAdminOS specific - disable wait-online service in host config

### SSH Not Accessible After Reboot
```bash
systemctl status netbird-homelab-enroll.service
systemctl status netbird-homelab.service
ip addr show nb-homelab
```
If enrollment failed, recreate setup key file and restart enroll service.

### Grafana Datasource Not Found
Provision datasources with explicit UIDs matching dashboard references.
See: `modules/grafana.nix`

## Migration Timeline

**Phase 1: Preparation**
- Created Netbird account, obtained API token
- Updated modules/networking.nix with multi-instance Netbird config
- Modified scripts.nix to generate/inject setup keys

**Phase 2: Test (t14)**
- First successful enrollment
- Verified dual-stack (WireGuard + Netbird)
- Discovered multi-instance daemon addressing requirement

**Phase 3: Rollout**
- Enrolled vpsfree, framework, thinkcenter, optiplex
- Tested inter-host connectivity
- Some hosts need local access for firewall updates

**Phase 4: DNS**
- Enabled Netbird embedded DNS (required CAP_NET_BIND_SERVICE)
- Migrated from *.vpn to *.krejci.io
- Verified service discovery working

**Phase 5: HTTPS**
- Generated Cloudflare API tokens
- Deployed Let's Encrypt wildcard certs
- Updated all services to HTTPS
- Hardened firewalls (localhost + nb-homelab only)

**Phase 6: Cleanup**
- Removed all WireGuard configuration
- Deleted WireGuard modules and keys
- Verified all services accessible via Netbird

## Domain Migration (vpn → krejci.io)

Domain changed from `*.vpn` to `*.krejci.io` for better organization and external DNS support.

**Changes:**
- Updated all service configurations
- Regenerated ACME certificates for new domain
- Updated Grafana datasources and dashboards
- Migrated DNS resolution to Netbird's built-in DNS

**Migration completed:** All services now use krejci.io domain with HTTPS.
