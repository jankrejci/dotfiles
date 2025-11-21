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

### NFS Mounts in vpsAdminOS
**Issue:** vpsAdminOS containers don't support systemd automount units (`x-systemd.automount`).

**Solution:** Use regular NFS mounts with vpsfree's recommended simple configuration:
```nix
fileSystems."/mnt/path" = {
  device = "nfs-server:/path";
  fsType = "nfs";
  options = ["nofail"];
};
```

**Avoid:** Additional options like `nfsvers=3`, `_netdev`, `noauto`, `x-systemd.automount` are unnecessary and may cause issues.

**Reference:** See vpsfree NFS documentation and `modules/backup-storage.nix` for working example.

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

### Public Interface Security Audit
Verify only intended ports are exposed on public interfaces:
```bash
# Scan specific ports
nmap -p 22,443,2283 <public-ip>

# Expected results:
# - Port 22 (SSH): filtered (blocked)
# - Port 443 (HTTPS): open (allowed)
# - Other ports: filtered (blocked)
```

**Understanding nmap results:**
- Full port scans (`nmap -p-`) show random filtered ports due to ICMP rate limiting
- This is normal firewall behavior, not actual open ports
- Use targeted scans or slow timing: `nmap -T2 --max-rate 100` for accuracy
- See: https://unix.stackexchange.com/questions/136683/why-are-some-ports-reported-by-nmap-filtered-and-not-the-others

**Critical**: All services must set `openFirewall = false` to prevent global firewall rules.
See: `modules/ssh.nix`, `modules/networking.nix`

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
- Enabled nftables, disabled global `openFirewall` on services
- Verified public interface security with nmap audits

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

## SSH Key Management Simplification

**Status:** ✅ COMPLETED

### Previous Approach
- Per-host SSH key files: `hosts/{hostname}/ssh-authorized-keys.pub`
- Fetched from GitHub via AuthorizedKeysCommand
- 9 separate files to manage

### New Approach
- Single central file: `ssh-authorized-keys.conf` (repo root)
- CSV format: `hostname, user, key`
- Supports multiple keys per hostname/user (multiple lines)
- Comments with `#`, spaces after commas allowed

### Benefits
- ✅ One file for all SSH keys (easier to manage)
- ✅ Flake check validates format: `nix flake check`
- ✅ Same caching mechanism (1 min cache, 5 min cleanup for revocation)
- ✅ Standard OpenSSH key format (no command restrictions in file)

### Implementation
- Modified `modules/ssh.nix`: Parse CSV format, filter by hostname/username
- Added `validate-ssh-keys` check in flake checks
- Migrated 25 keys from 9 hosts to central file
- AuthorizedKeysCommand receives username via `%u` token
- Refactored to use `writeShellApplication` for shellcheck validation

### Technical Details
**Script Structure:**
- `writeShellApplication` with `runtimeInputs` for explicit dependencies
- Functions: `fetch_keys_if_needed()`, `extract_keys()`, `main()`
- Atomic cache updates with temp files
- Never fails (always `exit 0`) to prevent sshd crashes

**Nix String Escaping:**
Shell variables in Nix strings must use `''${variable}` to prevent Nix interpolation:
```nix
matched=$(grep "^''${hostname}[[:space:]]*," file)
```

**Shellcheck Compatibility:**
- Unused variables: use `_` instead (e.g., `read -r _ user key`)
- `|| true` not needed - grep failures handled by conditionals before they exit
- Array syntax: always use braces `''${variable}` not `$variable`

### Deployment Experience
**fail2ban:** 10-minute IP bans after failed auth attempts (default 600s). Can lock you out during testing with wrong username. Unban with:
```bash
sudo fail2ban-client set sshd unbanip <ip>
```

**Testing:** Always verify script works standalone before deploying:
```bash
sudo /etc/fetch-authorized-keys admin
```

### Example
```
thinkcenter, admin, ssh-ed25519 AAAA... jkr-laptop
vpsfree, admin, ssh-ed25519 AAAA... jkr-laptop
vpsfree, borg, ssh-ed25519 AAAA... thinkcenter-backup
```

**Note:** For service accounts like `borg`, security is enforced via Unix file permissions (not SSH command restrictions).

## Backup Infrastructure

### Architecture
```
thinkcenter (Immich + Borg client)
    |
    | SSH: borg backup push
    ↓
vpsfree (Borg repository server)
    |
    | NFS mount (implementation detail)
    ↓
NAS (172.16.130.249:/nas/6057)
```

### Design Decisions

**Push vs Pull:**
- thinkcenter pushes backups to vpsfree (standard Borg SSH pattern)
- vpsfree mounts NAS and serves Borg repositories
- NAS accessible only from vpsfree network

**Security:**
- Dedicated `borg` user on vpsfree with restricted SSH access
- SSH key restricted with `command="borg serve --restrict-to-path /mnt/nas-backup/borg-repos/immich",restrict`
- Prevents: port forwarding, X11, arbitrary commands, access to other repos
- Borg encryption: repokey-blake2 (passphrase stored in /root/secrets)

**Backup Scope:**
- **Included:** `/var/lib/immich` (media files), PostgreSQL database dump
- **Excluded:** `/var/lib/immich/thumbs`, `/var/lib/immich/encoded-video` (regeneratable)

**Retention Policy:**
- Daily: 7 backups
- Weekly: 4 backups
- Monthly: 6 backups
- Total coverage: ~6 months

**Monitoring:**
- Prometheus already monitors thinkcenter node
- Backup metrics exposed via node_exporter
- Grafana dashboards track backup success/failure

### Implementation

**Status:** ✅ COMPLETED (2025-11-21)

**1. vpsfree (backup server):**
- `modules/backup-storage.nix`: NFS mount, borg user with bash shell
- Repository path: `/mnt/nas-backup/borg-repos/immich`
- NFS mount: `172.16.130.249:/nas/6057` → `/mnt/nas-backup` (250GB)
- Borg user has bash shell (required for `borg serve` command execution)
- Security via filesystem permissions (borg user owns /mnt/nas-backup/borg-repos)
- Status: ✅ DEPLOYED

**2. thinkcenter (Immich host):**
- `modules/immich.nix`: PostgreSQL dump service, Borg backup job
- Backup schedule: Daily at midnight (00:00)
- Pre-hook: dump database to `/var/backup/immich-db/immich.dump`
- Push to: `ssh://borg@vpsfree.krejci.io/mnt/nas-backup/borg-repos/immich`
- Status: ✅ DEPLOYED

**3. Initialization Steps:**

On thinkcenter:
```bash
# Generate backup SSH key
sudo ssh-keygen -t ed25519 -f /root/.ssh/borg-backup-key -N ""
sudo cat /root/.ssh/borg-backup-key.pub
# Copy the public key output for next step
```

Add the key to ssh-authorized-keys.conf (security via filesystem permissions, not SSH restrictions):
```bash
# Add this line to ssh-authorized-keys.conf in the repo
vpsfree, borg, ssh-ed25519 AAAA... thinkcenter-backup
```

Deploy configuration:
```bash
nix run .#deploy-config vpsfree
nix run .#deploy-config thinkcenter
```

On vpsfree (initialize repository):
```bash
# Verify NFS mount is active
df -h /mnt/nas-backup

# Initialize repository (one-time, needs HOME and passphrase)
sudo -u borg HOME=/tmp BORG_PASSPHRASE='your-passphrase' borg init --encryption=repokey-blake2 /mnt/nas-backup/borg-repos/immich
```

On thinkcenter:
```bash
# Create passphrase file (use same passphrase from borg init)
sudo mkdir -p /root/secrets
echo "your-passphrase" | sudo tee /root/secrets/borg-passphrase
sudo chmod 600 /root/secrets/borg-passphrase

# Test SSH connection (should see "This account is currently not available")
sudo ssh -i /root/.ssh/borg-backup-key borg@vpsfree.krejci.io
# This is expected - borg protocol works despite nologin message

# Test backup
sudo systemctl start borgbackup-job-immich
sudo journalctl -u borgbackup-job-immich -f
```

**4. Restore Procedure:**

```bash
# List backups
sudo borg list ssh://borg@vpsfree.krejci.io/mnt/nas-backup/borg-repos/immich

# Restore media files
sudo borg extract ssh://borg@vpsfree.krejci.io/mnt/nas-backup/borg-repos/immich::archive-name var/lib/immich

# Restore database
sudo -u postgres pg_restore -d immich /var/backup/immich-db/immich.dump
```

### Deployment Experience

**Initial backup (2025-11-21):**
- Duration: 17 minutes
- Data processed: 37 GB
- Uploaded (compressed): 18.3 GB
- Compression ratio: ~51% with zstd

**Systemd timer activation:**
After deployment, systemd may not immediately recognize new timer units. Solution: reboot the host or wait for next boot cycle. Timer files exist in `/run/current-system/etc/systemd/system/` but systemd needs to reload its unit cache.

**Borg user shell requirement:**
Initially used `nologin` shell for security, but borg requires executing `borg serve` command on remote side. Changed to bash shell with security enforced via filesystem permissions (borg user owns `/mnt/nas-backup/borg-repos`, mode 0700).

**Repository initialization gotcha:**
Borg user (system user with `/var/empty` home) cannot write config. Use `HOME=/tmp` during `borg init`:
```bash
sudo -u borg HOME=/tmp BORG_PASSPHRASE='...' borg init --encryption=repokey-blake2 /path/to/repo
```

### Benefits
- Centralized storage on NAS (250GB allocation)
- Off-host backups (thinkcenter failure doesn't lose backups)
- Encrypted at rest and in transit (repokey-blake2)
- Deduplication and compression (~50% space savings)
- Monitored via existing Prometheus/Grafana stack
- Automatic retention management (7 daily, 4 weekly, 6 monthly)
