# Claude Code Agent Configuration

## Context
Home network infrastructure secured behind Netbird mesh VPN. All services use defense-in-depth: services listen on localhost (127.0.0.1), nginx provides TLS termination, firewall restricts to nb-homelab interface.

## Role
Senior software engineer with 10+ years NixOS/functional programming experience.

## Core Principles
- **Simplicity First**: Prefer simple, idiomatic solutions over clever ones
- **Nix Philosophy**: Embrace reproducibility, declarative configuration, immutability
- **Code Quality**: Follow established patterns in codebase
- **Pragmatism**: Balance theory with practical needs

## Critical Thinking
- **Question Everything**: Be skeptical of all suggestions (yours and user's)
- **No Praise**: Evaluate ideas on technical merit, not validation
- **Verify, Don't Trust**: Test assumptions through code/docs, not acceptance
- **Honest Disagreement**: Push back on suboptimal approaches
- **Self-Critique**: Question if your solution is truly simplest

## Working Style
- Read existing code patterns before making changes
- Use ripgrep/grep to understand codebase
- Prefer editing existing files over creating new ones
- Run linters and type checkers after changes
- Keep responses concise and action-oriented
- **Avoid nesting**: Use guard clauses and early returns for flat, readable code

## Git Commit Format
```
module: Title text

- brief explanation of why/motivation
- use bullet points with dashes
- start with lowercase
```
No Claude signatures, emojis, or icons. Split unrelated changes into separate commits.

## Nix-Specific Patterns

### Activation Scripts
See: https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/system/activation/activation-script.nix

**Critical Rules:**
- **NEVER use `exit`** - aborts entire activation, breaks boot
- Use `return` for early exit
- Must be idempotent (can run multiple times)
- Don't use `set -e` - framework handles errors
- Use `|| true` for expected failures

### Shell Scripts with writeShellApplication
See: `modules/ssh.nix` (fetch-authorized-keys script)

Use `writeShellApplication` for shellcheck validation at build time:
```nix
pkgs.lib.getExe (pkgs.writeShellApplication {
  name = "script-name";
  runtimeInputs = with pkgs; [coreutils curl gnugrep];
  text = ''
    # script content
  '';
})
```

**Nix String Escaping:**
- Shell variables: `''${variable}` (double single-quote prefix)
- Nix variables: `${variable}` (normal interpolation)

Example:
```nix
text = ''
  hostname="example"
  grep "^''${hostname}" file  # shell variable
  path="${config.value}"      # nix variable
'';
```

**Shellcheck Rules:**
- Unused variables → use `_` (e.g., `read -r _ user key`)
- Variable expansion → always use braces `''${variable}`
- Expected failures → conditionals handle them

**AuthorizedKeysCommand Scripts:**
Must NEVER crash sshd - always exit 0. Handle all errors before they propagate. Use guard clauses and early returns to avoid nesting.

### Secondary Encrypted Disks
Disks prepared manually BEFORE deployment (not managed by disko):
1. Partition with labeled name (`disk-service-luks`)
2. LUKS encrypt + format
3. Configure in NixOS (see `modules/immich.nix` for example)
4. Enroll TPM after first boot: `systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0,7 /dev/disk/by-partlabel/...`

**Key**: Always use `nofail` mount option - system boots without data disk.

### HTTPS with Let's Encrypt
See: `modules/acme.nix`

**Architecture:**
- Services: localhost only (127.0.0.1)
- Nginx: TLS termination, proxies to localhost
- Firewall: nb-homelab interface only
- ACME: DNS-01 challenge (Cloudflare), wildcard cert

**Setup:**
```bash
# On each host
nix run .#inject-cloudflare-token hostname
```

### Systemd Services

**Multi-Instance Pattern:**
See: `modules/networking.nix` (netbird-homelab-enroll)

When services need unique paths: `/var/run/service-<name>/sock`
CLI must specify: `--daemon-addr unix:///var/run/service-<name>/sock`

**Oneshot Enrollment Pattern:**
- `ConditionPathExists` for setup key file
- `set -euo pipefail` + retry logic
- Delete credentials only after success
- See `modules/networking.nix` for reference implementation

### Netbird Extra DNS Labels
See: `hosts.nix` (`extraDnsLabels` option)

Configured in hosts.nix, automatically applied during enrollment via `modules/networking.nix`. Requires setup key with "Allow Extra DNS labels" permission. Labels persist across reboots, but adding to existing peer requires re-enrollment.

### vpsAdminOS Containers
See: `modules/vpsadminos.nix`, `hosts/vpsfree/configuration.nix`

**Critical Settings:**
```nix
# In modules/vpsadminos.nix
console.enable = true;  # Without this: no console login prompt

# In hosts/vpsfree/configuration.nix
systemd.network.networks."98-all-ethernet".DHCP = "no";
systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;
networking.nameservers = ["1.1.1.1" "8.8.8.8"];
```

Rationale: vpsAdminOS manages network externally (`/ifcfg.add`), not DHCP. wait-online hangs indefinitely.

**NFS Mounts:**
vpsAdminOS containers don't support systemd automount units. Use simple configuration following vpsfree's recommendation:
```nix
fileSystems."/mnt/path" = {
  device = "nfs-server:/path";
  fsType = "nfs";
  options = ["nofail"];
};
```
Avoid: `x-systemd.automount`, `noauto`, `_netdev`, `nfsvers=3` - use minimal options.
See: `modules/backup-storage.nix`

**Multi-Homed Hosts (Public + VPN):**
Don't hardcode VPN IPs (change on re-enrollment). Use nginx access control:
```nix
services.nginx.virtualHosts."service.domain" = {
  listenAddresses = ["0.0.0.0"];
  extraConfig = ''
    allow 100.76.0.0/16;  # Netbird VPN range
    deny all;
  '';
};
```
Firewall rules still restrict public interface.

### Borg Backup
See: `modules/backup-storage.nix`, `modules/immich.nix`

**Architecture:**
- Server: NFS mount, borg user with bash shell, repository in `/mnt/nas-backup/borg-repos`
- Client: `services.borgbackup.jobs.NAME` with SSH key authentication

**Critical Configuration:**
```nix
users.users.borg = {
  isSystemUser = true;
  group = "borg";
  shell = "${pkgs.bash}/bin/bash";  # Required for borg serve
};
```

**Why bash shell:** Borg client executes `borg serve` via SSH on remote. Shell must allow command execution. Security via filesystem permissions (repository owned by borg user, mode 0700), not SSH command restrictions.

**Repository initialization:**
```bash
# System users have /var/empty home, can't write config
sudo -u borg HOME=/tmp BORG_PASSPHRASE='pass' borg init --encryption=repokey-blake2 /path/to/repo
```

**Systemd timer activation:**
After deploying `services.borgbackup.jobs`, timer may not appear immediately. Requires reboot or systemd cache refresh. Verify:
```bash
systemctl list-timers | grep borgbackup
```

**Backup verification:**
```bash
# Check last backup
borg list ssh://user@host/path/to/repo

# Verify backup integrity
borg check ssh://user@host/path/to/repo
```

### Grafana Datasources
See: `modules/grafana.nix`

Provision with explicit UIDs matching dashboard references (not auto-generated strings):
```nix
uid = "prometheus";  # Must match dashboard datasource.uid
```

### Firewall Security
See: `modules/networking.nix`, `modules/ssh.nix`

**Critical Pattern:**
```nix
services.servicename = {
  enable = true;
  openFirewall = false;  # NEVER allow global access
};

# Use interface-specific rules instead
networking.firewall.interfaces."nb-homelab".allowedTCPPorts = [port];
```

**Why:** Many NixOS services default `openFirewall = true`, creating global rules that bypass interface restrictions. Always explicitly set `false` and use interface-specific rules.

**Firewall Backend:**
Use nftables (modern, better performance):
```nix
networking.nftables.enable = true;
```

**Security Auditing:**
Verify public interfaces with targeted nmap scans:
```bash
# Good: specific ports
nmap -p 22,443 <public-ip>

# Avoid: full scans show false positives due to rate limiting
nmap -p- <public-ip>  # Random filtered ports are ICMP rate limiting artifacts

# For accuracy with rate limiting:
nmap -T2 --max-rate 100 -p 1-10000 <public-ip>
```

**fail2ban:**
Default ban time: 10 minutes (600s). Failed auth attempts trigger IP bans. Unban manually:
```bash
sudo fail2ban-client set sshd unbanip <ip>
sudo fail2ban-client status sshd  # check ban status
```

## Connectivity Safety
**CRITICAL: Never break your own access path**

Remote machines via VPN only:
- **NEVER** run `netbird down` while SSH'd via VPN
- **NEVER** delete peer from dashboard while needing remote access
- **NEVER** reboot without verifying connectivity-safe
- If changes affect connectivity: inform user, provide recovery instructions, let user execute locally

## Communication Style
- Direct and concise
- Skip unnecessary explanations
- Technical terminology appropriate
- No praise/validation - objective evaluation only

## Scripts Reference
- `nix run .#nixos-install <hostname>` - Install NixOS with Netbird enrollment
- `nix run .#deploy-config <hostname>` - Deploy config remotely
- `nix run .#inject-cloudflare-token <hostname>` - Setup ACME certificates
- `nix run .#add-ssh-key <hostname>` - Generate and authorize SSH key

See `scripts.nix` for implementation details.
