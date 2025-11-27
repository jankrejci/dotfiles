# NetBird Self-Hosted Migration

## Executive Summary

**Status:** Planning Phase
**Migration:** Netbird Cloud → Self-Hosted Netbird
**Architecture:** vpsfree (public gateway) + thinkcenter (control plane) via WireGuard tunnel

### Key Requirements Met

1. ✅ **Management downtime resilience:** Existing WireGuard tunnels continue working
2. ✅ **vpsfree security:** Only reverse proxy + relay (no sensitive data)
3. ✅ **NAT traversal:** vpsfree acts as public gateway to thinkcenter behind NAT
4. ✅ **Simplicity:** Standard nginx reverse proxy + WireGuard tunnel
5. ✅ **Google SSO:** Natively supported via OIDC configuration
6. ✅ **Setup keys:** Standard feature, stored in sops


## Architecture

### Core Services

**Management (Port 33073):** Network state, peer registration, authentication, policies. Uses PostgreSQL. No HA support - single instance only. Downtime doesn't affect existing peer connections.

**Signal (Port 10000):** Stateless peer discovery for WebRTC negotiation. End-to-end encrypted, no data persistence.

**Relay (Port 33080):** Fallback transport for NAT traversal (replaced Coturn). Supports multiple instances, stateless, sees only encrypted traffic.

**Dashboard (80/443):** Web UI via nginx reverse proxy.

**Identity Provider:** OIDC authentication. Using Google SSO - natively supported by NetBird.

### Component Split

**vpsfree (Public):** Nginx reverse proxy (TLS termination, gRPC/HTTP proxy to thinkcenter:10.100.0.1 for management), signal server, relay server, ACME certificates. No database, no network state, no credentials.

**thinkcenter (Private):** Management server, PostgreSQL, dashboard (nginx on port 8080). All secrets via sops, encrypted disk, firewall restricted to WireGuard tunnel.

### High Availability

**Not Supported:** Management server cannot run multiple instances (storage backends don't support concurrent access).

**Mitigation:** Dual Borg backups (local + remote), quick recovery (RTO: 2-4 hours), existing peer connections survive downtime.

**Supported:** Multiple relay servers (geographic distribution), network route HA (multiple routing peers for failover).

## Prerequisites

### 1. WireGuard Tunnel (vpsfree ↔ thinkcenter)

Independent of Netbird (no circular dependency). Tunnel on 10.100.0.0/30:
- vpsfree: 10.100.0.2
- thinkcenter: 10.100.0.1

**Configuration notes:**
- Generate WireGuard keypairs with `wg genkey`
- Store private keys in sops
- Configure persistent keepalive (25 seconds)
- Firewall: allow UDP 51820 on both hosts
- vpsfree endpoint: `<vpsfree-public-ip>:51820`
- thinkcenter: no endpoint (behind NAT, responds to vpsfree)

### 2. DNS Configuration

Add DNS record: `netbird.krejci.io  A  <vpsfree-public-ip>`

Verify: `dig netbird.krejci.io +short`

### 3. Google OAuth Application

**Google Cloud Console setup:**
1. Create project "NetBird Self-Hosted"
2. OAuth consent screen:
   - User Type: External
   - Authorized domains: `krejci.io`
   - Scopes: `openid`, `email`, `profile` (default)
3. Create OAuth 2.0 Client ID (Web application):
   - Authorized JavaScript origins: `https://netbird.krejci.io`
   - Authorized redirect URIs:
     - `https://netbird.krejci.io/auth/callback`
     - `https://netbird.krejci.io/silent-auth`
4. Save Client ID and Client Secret

**NetBird integration:**
- NetBird natively supports Google SSO via OIDC
- Configure management server with:
  - Auth issuer: `https://accounts.google.com`
  - OIDC endpoint: `https://accounts.google.com/.well-known/openid-configuration`
  - Client ID and secret from Google Console
- First user to login becomes admin automatically
- NetBird handles all OAuth flows, token management, user mapping

### 4. Cloudflare API Token

Required for Let's Encrypt DNS-01 challenge. Create token with "Edit zone DNS" permission for `krejci.io` zone.

## Secrets Management

**Approach:** Deploy infrastructure first, inject secrets afterward using injection scripts.

**Secrets needed:**

**WireGuard:**
- `wg-vpsfree-private` (thinkcenter)
- `wg-thinkcenter-private` (vpsfree)

**NetBird:**
- `netbird-data-encryption-key` (thinkcenter) - PostgreSQL data encryption
- `netbird-relay-secret` (both hosts) - shared secret for relay
- `netbird-google-client-id` (thinkcenter)
- `netbird-google-client-secret` (thinkcenter)

**Borg Backup:**
- `netbird-borg-passphrase-local` (thinkcenter)
- `netbird-borg-passphrase-remote` (thinkcenter)

**Other:**
- `cloudflare-api-token` (vpsfree) - for ACME

**Storage:** All secrets stored in sops, accessed at `/run/secrets/<name>` by services.

**Injection scripts:** Create injection scripts similar to existing patterns (`inject-cloudflare-token`, `inject-borg-passphrase`).

## Configuration

### thinkcenter: Management + Signal + Dashboard

**WireGuard tunnel:**
- Interface: `wg-vpsfree`
- IP: `10.100.0.1/30`
- Listen port: 51820
- Private key: `/run/secrets/wg-vpsfree-private`
- Peer: vpsfree public key, allowed IPs `10.100.0.2/32`, endpoint `<vpsfree-ip>:51820`, keepalive 25

**PostgreSQL:**
- Enable PostgreSQL 16
- Create database: `netbird`
- Create user: `netbird` with ownership
- Authentication: peer (Unix socket)
- Backup: daily at 3 AM to `/var/backup/postgresql`

**NetBird management server:**
- Domain: `netbird.krejci.io`
- Disable built-in nginx (handle separately)
- Management settings:
  - Store engine: PostgreSQL
  - Data encryption key: `/run/secrets/netbird-data-encryption-key`
  - Listen: `0.0.0.0:33073`
  - Auth issuer: `https://accounts.google.com`
  - Auth audience: client ID from `/run/secrets/netbird-google-client-id`
  - OIDC endpoint: `https://accounts.google.com/.well-known/openid-configuration`
  - Signal: `https://netbird.krejci.io:10000`
  - Relay: `rel://netbird.krejci.io:33080` with secret from `/run/secrets/netbird-relay-secret`
  - IDP manager: Google with client ID/secret from sops
  - Device auth flow: hosted with Google OAuth
- PostgreSQL DSN: `host=/run/postgresql user=netbird dbname=netbird sslmode=disable`

**Dashboard (nginx):**
- Listen: `0.0.0.0:8080`
- Serve: `${pkgs.netbird-dashboard}`
- Try files: `$uri $uri/ /index.html`

**Firewall:**
- Public: nothing TCP, only UDP 51820 (WireGuard)
- Restricted to vpsfree (10.100.0.2):
  - TCP 33073 (management)
  - TCP 8080 (dashboard)

**Borg backup:**
- Local job:
  - Paths: `/var/backup/postgresql`, `/var/lib/netbird`
  - Repo: `/var/lib/borg-repos/netbird`
  - Encryption: repokey
  - Passphrase: `/run/secrets/netbird-borg-passphrase-local`
  - Compression: auto,zstd
  - Schedule: daily
  - Retention: 7 daily, 4 weekly, 6 monthly
- Remote job:
  - Same paths
  - Repo: `borg@vpsfree.krejci.io:/var/lib/borg-repos/netbird`
  - Passphrase: `/run/secrets/netbird-borg-passphrase-remote`
  - Retention: 7 daily, 4 weekly, 3 monthly

**Sops secrets:**
- Configure access for thinkcenter to all netbird secrets, borg passphrases, wg private key

### vpsfree: Reverse Proxy + Relay

**WireGuard tunnel:**
- Interface: `wg-thinkcenter`
- IP: `10.100.0.2/30`
- Listen port: 51820
- Private key: `/run/secrets/wg-thinkcenter-private`
- Peer: thinkcenter public key, allowed IPs `10.100.0.1/32`, keepalive 25

**Nginx reverse proxy:**
- Enable recommended proxy and gzip settings
- Virtual host: `netbird.krejci.io`
  - ACME: enabled
  - Force SSL: yes
  - Access control (enable after migration):
    - Allow: 100.64.0.0/10 (Netbird CGNAT range)
    - Deny: all
  - Location `/`: proxy to `http://10.100.0.1:8080` (dashboard)
  - Location `/management.ManagementService/`: gRPC proxy to `10.100.0.1:33073`
  - Set headers: Host, X-Real-IP, X-Forwarded-For, X-Forwarded-Proto

**ACME:**
- Accept terms
- Email: `admin@krejci.io`
- Certificate for `netbird.krejci.io`:
  - DNS provider: Cloudflare
  - Credentials: `/run/secrets/cloudflare-api-token`

**Signal server:**
- Systemd service: `netbird-signal`
- Command: `netbird signal run --listen-address :10000`
- Restart: always
- DynamicUser: true

**Relay server:**
- Systemd service: `netbird-relay`
- Command: `netbird relay run --listen-address :33080 --secret-file /run/secrets/netbird-relay-secret`
- Restart: always
- DynamicUser: true

**Firewall:**
- TCP: 80 (HTTP), 443 (HTTPS), 10000 (signal), 33080 (relay WebSocket)
- UDP: 51820 (WireGuard), 33080 (relay QUIC)

**Sops secrets:**
- Configure access for vpsfree to relay secret, wg private key, cloudflare token

## Migration Procedure

### Phase 1: Infrastructure Setup

1. **Add DNS:** `netbird.krejci.io A <vpsfree-public-ip>`, verify propagation
2. **Generate WireGuard keys:** Generate keypairs, note public keys for peer config
3. **Deploy configurations:** Deploy both hosts with WireGuard + service configs (secrets injected next)
4. **Inject secrets:** Run injection scripts to populate sops secrets on both hosts
5. **Verify WireGuard:** Check `wg show`, test `ping 10.100.0.1` ↔ `ping 10.100.0.2`
6. **Verify services:**
   - thinkcenter: PostgreSQL, netbird-management, nginx (dashboard)
   - vpsfree: nginx, ACME cert obtained, netbird-signal, netbird-relay
7. **Test connectivity:** `curl -I https://netbird.krejci.io` should return 200
8. **Initial dashboard access:** Open `https://netbird.krejci.io`, login with Google

### Phase 2: Test Enrollment

1. **Create test group:** Dashboard → Settings → Groups → "test-migration"
2. **Generate setup key:** Reusable, 7 days expiry, auto-assign to test group
3. **Enroll test peers:** On 2 test machines:
   - Disconnect from cloud: `netbird down`
   - Remove config: `sudo rm /etc/netbird/config.json`
   - Enroll: `netbird up --management-url https://netbird.krejci.io:443 --setup-key <KEY>`
4. **Test connectivity:** Ping between peers, check connection type (Direct/Relayed)
5. **Test relay fallback (optional):** Block direct connection, verify relay works

### Phase 3: Migrate Peers

1. **Document cloud setup:** Screenshot peers, groups, policies, routes, DNS labels from cloud dashboard
2. **Recreate structure:** In self-hosted dashboard, create all groups, policies, routes, DNS settings
3. **Generate setup keys:** Create reusable keys per group (servers, workstations), store in sops
4. **Migrate peers in order:**
   - Non-critical first (rpi4, prusa)
   - Console-access machines
   - Secondary workstation
   - Servers (thinkcenter, vpsfree)
   - **LAST:** Primary workstation

**Per-peer process:**
- SSH to peer
- Stop cloud connection: `netbird down`
- Remove config: `sudo rm /etc/netbird/config.json`
- Enroll self-hosted: `netbird up --management-url https://netbird.krejci.io:443 --setup-key <KEY>`
- Verify: `netbird status`

**Automated enrollment (NixOS):**
- Create systemd oneshot service
- ConditionPathExists on setup key file
- Check if already enrolled (grep for netbird.krejci.io in status)
- Retry logic (3 attempts with 5s sleep)
- Error handling (set -euo pipefail)
- Multi-instance support: use `--daemon-addr unix:///var/run/netbird-homelab/sock` if needed

**Expected downtime per peer:** 2-5 minutes

### Phase 4: Cleanup

1. **Verify migration:** Check peer count, test connectivity between all peers
2. **Enable access control:** Uncomment nginx IP allowlist on vpsfree, deploy
3. **Test backups:** Verify borg timers active, test restore (dry run)
4. **Update documentation:** Update CLAUDE.md with new architecture notes
5. **Delete cloud account (optional):** Export final config, delete cloud account

## Key Configuration Patterns

### Multi-Instance Netbird

When running multiple Netbird instances, specify daemon address:
`netbird --daemon-addr unix:///var/run/netbird-homelab/sock status`

### Setup Key Best Practices

- Use ConditionPathExists for idempotency
- Check enrollment status before attempting
- Implement retry logic for timing issues
- Use set -euo pipefail for error handling

### VPN IP Stability

Netbird assigns new IPs on re-enrollment. Use DNS names, not IPs. For nginx access control, use CGNAT range (100.64.0.0/10) not individual peer IPs.

### Extra DNS Labels

Setup keys need "Allow Extra DNS labels" permission. Labels applied during enrollment. To modify: delete peer and re-enroll.

## Troubleshooting

### WireGuard Tunnel

Check handshake: `wg show wg-vpsfree` (expect recent handshake < 2 min)
Test connectivity: `ping 10.100.0.2`
Check firewall: `nft list ruleset | grep 51820`
Restart: `systemctl restart systemd-networkd`

### Reverse Proxy

Check nginx: `systemctl status nginx; nginx -t`
Test backend: `curl -v http://10.100.0.1:8080` (from vpsfree)
Check ACME: `systemctl status acme-netbird.krejci.io`
Logs: `journalctl -u nginx -f`

### Management Server

Check services: `systemctl status netbird-management postgresql`
Logs: `journalctl -u netbird-management -n 100`
Verify PostgreSQL: `sudo -u postgres psql netbird -c "\dt"`
Check ports: `ss -tlnp | grep -E "(33073|8080)"`

### Signal/Relay Servers (vpsfree)

Check services: `systemctl status netbird-signal netbird-relay`
Logs: `journalctl -u netbird-signal -n 50; journalctl -u netbird-relay -n 50`
Check ports: `ss -tlnp | grep -E "(10000|33080)"`

### Google OAuth

Check logs: `journalctl -u netbird-management | grep -i oauth`
Verify OIDC endpoint: `curl https://accounts.google.com/.well-known/openid-configuration`
Common issues: redirect URI mismatch, wrong client ID/secret, consent screen not configured

### Peer Connection Issues

Debug: `netbird up --log-level debug --management-url https://netbird.krejci.io:443 --setup-key <KEY>`
Logs: `journalctl -u netbird -f`
Test reachability: `curl https://netbird.krejci.io/`
Common issues: invalid/expired key, firewall, DNS resolution

Test endpoints:
- Signal: `nc -zv netbird.krejci.io 10000`
- Relay: `nc -zv netbird.krejci.io 33080`
Verify relay secret matches on vpsfree and thinkcenter management config

### Disaster Recovery

Peers continue working during management downtime. To restore:
1. Extract latest backup: `borg extract /var/lib/borg-repos/netbird::latest`
2. Restore database: `sudo -u postgres psql netbird < backup/postgresql/netbird.sql`
3. Deploy config: `nix run .#deploy-config thinkcenter`

Expected RTO: 2-4 hours

## Security

### Defense in Depth

**vpsfree:** TLS 1.2+, modern ciphers, HSTS, IP allowlist (100.64.0.0/10 after migration), rate limiting (optional), no sensitive data at rest, fail2ban (optional).

**thinkcenter:** No public exposure, PostgreSQL peer auth (Unix socket only), sops for secrets, encrypted disk, firewall restricts to WireGuard tunnel (10.100.0.2 only).

### Monitoring

**Prometheus/Grafana metrics:**
- Service health: netbird-management, netbird-signal, netbird-relay, postgresql, nginx
- WireGuard tunnel: handshake age, packet loss
- PostgreSQL: connection count, database size, backup completion
- Nginx: request rate, error rate, response times for netbird.krejci.io
- Disk usage: PostgreSQL data, borg repositories
- Backup jobs: last success timestamp, job duration

**Manual checks (weekly):**
- Review nginx access logs: `journalctl -u nginx --since "7 days ago" | grep netbird.krejci.io`
- Check peer status in dashboard
- Verify backup integrity: `borg list /var/lib/borg-repos/netbird`

## Maintenance

**Weekly:** Review Grafana dashboards, check peer status in NetBird dashboard, verify backups completed

**Monthly:** Update nixpkgs (`nix flake update`), deploy updates, test backup restore (dry run), review nginx access logs for anomalies

**Quarterly:** Disaster recovery drill, review access policies, check security advisories (`https://github.com/netbirdio/netbird/security/advisories`), rotate OAuth credentials if needed

## References

- Self-hosting guide: https://docs.netbird.io/selfhosted/selfhosted-guide
- How NetBird works: https://docs.netbird.io/about-netbird/how-netbird-works
- PostgreSQL store: https://docs.netbird.io/selfhosted/postgres-store
- Identity providers: https://docs.netbird.io/selfhosted/identity-providers
- NixOS module: https://mynixos.com/options/services.netbird.server
- Management HA discussion: https://github.com/netbirdio/netbird/issues/1584

## Changelog

### 2025-11-27 - Configuration Notes Format
- Removed all code blocks, replaced with configuration notes
- Changed from agenix to sops for secrets management
- Changed to inject-after-deploy workflow
- Reduced to ~400 lines focused on planning and decisions

### 2025-11-27 - Documentation Condensed
- Reduced from 1930 to 650 lines
- Maintained comprehensive reference information
- Removed verbose examples, consolidated redundant sections

### 2025-11-25 - Initial Planning
- Analyzed NetBird self-hosted architecture
- Designed split architecture (vpsfree gateway + thinkcenter control plane)
- Documented migration strategy and procedures
- Validated architecture meets all requirements
