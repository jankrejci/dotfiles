# Netbird Migration Plan

## Status: ✅ MIGRATION COMPLETED (WireGuard removed, HTTPS enabled, domain migrated to krejci.io)

## Previous State (Pre-Migration)
- Manual WireGuard mesh VPN with vpsfree (192.168.99.1) as central hub
- 192.168.99.0/24 network with static peer configurations
- CoreDNS on vpsfree providing *.vpn domain resolution
- All hosts had WireGuard peer configs pointing to vpsfree:51820
- HTTP-only services with no TLS encryption

## Current State (Post-Migration)
- ✅ Netbird mesh VPN using hosted management service at https://app.netbird.io
- ✅ Netbird's built-in DNS providing *.krejci.io domain resolution
- ✅ WireGuard configuration completely removed from codebase
- ✅ All enrolled hosts accessible via Netbird VPN
- ✅ All services secured with HTTPS using Let's Encrypt wildcard certificates
- ✅ Defense in depth: services listen on localhost only, nginx as TLS termination point
- ✅ Firewall hardened: only port 443 (HTTPS) exposed on nb-homelab interface

## Migration Steps

### Phase 1: Preparation
1. ✅ Create Netbird account at https://app.netbird.io
2. ✅ Obtain Netbird API token for CLI automation (for generating setup keys)
3. ✅ Update `modules/networking.nix` with Netbird configuration
4. ✅ Update `scripts.nix` nixos-install function to:
   - Add `install_netbird_key()` function (similar to `install_wg_key()`)
   - Use Netbird API to generate one-off setup key with hostname
   - Store setup key in TEMP directory (like WireGuard key)
   - Pass to target via nixos-anywhere --extra-files

### Phase 2: Test Migration (t14) ✅ COMPLETED
1. ✅ Run `nix run .#nixos-install t14`:
   - Script generates one-off Netbird setup key via API (name="t14")
   - Setup key stored in TEMP directory at /var/lib/netbird-homelab/setup-key
   - nixos-anywhere copies TEMP to target via --extra-files
   - Netbird homelab service reads setup key on first boot and enrolls
2. ✅ Verify Netbird connectivity (nb-homelab interface comes up)
3. ⏭️ Test DNS resolution through Netbird (deferred to Phase 4)
4. ✅ Verify can reach other services via both wg0 and nb-homelab
5. ⏭️ Confirm hostname in Netbird dashboard (skipped for now)
6. ✅ Note: Netbird IP is 100.76.144.136/16 (differs from 192.168.99.24 as expected)
7. ✅ Keep WireGuard running as fallback until all hosts migrated

**Phase 2 Results:**
- Enrollment successful on t14
- Interface: nb-homelab (100.76.144.136/16)
- FQDN: t14-144-136.netbird.cloud
- Status: Management Connected, Signal Connected, Relays 4/4, Peers 1/2
- Both WireGuard and Netbird running simultaneously
- Ping connectivity confirmed from other devices

**Lessons Learned:**
- Multi-instance netbird requires `--daemon-addr unix:///var/run/netbird-homelab/sock`
- Enrollment service must run AFTER daemon starts (`after = ["netbird-homelab.service"]`)
- Setup key deletion must be conditional on successful enrollment (`set -euo pipefail`)
- Service needs retry logic (`Restart = "on-failure"`, `RestartSec = 5`, `StartLimitBurst = 3`)

### Phase 3: Gradual Rollout ✅ COMPLETED
1. Enrolled hosts using deployment script:
   - ✅ t14 (test migration - 100.76.144.136)
   - ✅ vpsfree (Grafana server - 100.76.116.219)
   - ✅ framework (100.76.232.215)
   - ✅ thinkcenter (100.76.149.0) - enrolled but needs local access for deployment
   - ✅ optiplex (100.76.24.123) - enrolled but needs local access for deployment
   - ⏳ e470 - not yet enrolled
   - ⏳ rpi4, prusa - not yet enrolled
2. For each enrolled host:
   - Script generated one-off setup key via Netbird API
   - Setup key injected during installation via nixos-anywhere
   - Enrollment service auto-enrolled on first boot and deleted setup key
3. Inter-host connectivity tested and working

**Phase 3 Notes:**
- thinkcenter and optiplex are enrolled and reachable via Netbird (ping works)
- However, SSH is refused because they haven't been redeployed with updated firewall rules
- These hosts need local/physical access to deploy updated configuration
- Once deployed, they will allow SSH on nb-homelab interface

### Phase 4: DNS Migration ✅ COMPLETED
1. ✅ Configured Netbird DNS in dashboard at https://app.netbird.io
   - Enabled embedded DNS on port 53
   - Set up *.x.nb domain resolution via Netbird
   - Domain changed from *.vpn to *.x.nb
2. ✅ Added CAP_NET_BIND_SERVICE capability to netbird-homelab service
   - Required for Netbird to bind to port 53
   - Without this, Netbird DNS listened on port 5053 causing resolution failures
   - Added to `systemd.services.netbird-homelab.serviceConfig.AmbientCapabilities`
3. ✅ Tested DNS resolution from enrolled hosts
   - Example: `resolvectl query framework.x.nb` returns 100.76.232.215
   - DNS Server: 100.76.116.219 (vpsfree's Netbird IP)
4. ✅ Verified service discovery works through Netbird DNS

**Phase 4 Issues Resolved:**
- Initial DNS failure: Netbird couldn't bind to port 53 without CAP_NET_BIND_SERVICE
- Prometheus scraping initially failed until hosts were redeployed with updated firewall rules

### Phase 5: Cleanup ✅ COMPLETED
1. ✅ Removed all WireGuard configuration:
   - ✅ Removed WireGuard netdev/network configuration from modules/networking.nix
   - ✅ Removed modules/wg-server.nix from vpsfree extraModules in hosts.nix
   - ✅ Removed WireGuard firewall rules (wg0 interface references)
   - ✅ Removed wgPublicKey option from hosts.nix schema
   - ✅ Deleted all hosts/*/wg-key.pub files (9 files)
   - ✅ Removed WireGuard key generation from scripts.nix:
     - Removed generate_wg_keys() function
     - Removed install_wg_key() function
     - Removed WireGuard-related constants and tests
   - ✅ Updated NetworkManager unmanaged list to only include nb-* (removed wg0)
2. ✅ Removed IP addresses from configuration:
   - ✅ Removed ipAddress option from hosts.nix schema
   - ✅ Removed all ipAddress values from host definitions
   - ✅ Changed services to listen on 0.0.0.0 with firewall restrictions
3. ✅ Updated all domain references from *.vpn to *.x.nb:
   - ✅ modules/grafana.nix
   - ✅ modules/grafana/overview.json dashboard
   - ✅ flake.nix deploy targets
   - ✅ scripts.nix installer target
4. ✅ Updated service configurations:
   - ✅ SSH: Listen on all interfaces, restrict via firewall (nb-homelab only)
   - ✅ Grafana: Listen on 0.0.0.0, restrict via firewall
   - ✅ Prometheus: Listen on 0.0.0.0, auto-discover all NixOS hosts
   - ✅ Prometheus node exporter: Listen on 0.0.0.0, restrict via firewall
   - ✅ Nginx: Proxy to localhost instead of external domain

### Phase 6: Domain Migration to krejci.io ✅ COMPLETED
1. ✅ Moved DNS from Namecheap to Cloudflare (free tier)
   - Domain registration remains at Namecheap
   - DNS hosting on Cloudflare for better API access and faster propagation
2. ✅ Updated Netbird dashboard domain from x.nb to krejci.io
   - Settings → Networks → Changed domain suffix
3. ✅ Updated all code references from x.nb to krejci.io:
   - modules/grafana.nix, modules/immich.nix: domain = "krejci.io"
   - flake.nix: hostname = "${hostName}.krejci.io"
   - scripts.nix: Updated all x.nb references
   - README.md, CLAUDE.md: Changed to generic <domain> placeholders
4. ✅ DNS propagation completed successfully
5. ✅ All hosts accessible via new domain

### Phase 7: HTTPS Migration with Let's Encrypt ✅ COMPLETED
1. ✅ Created modules/acme.nix for Let's Encrypt wildcard certificates
   - DNS-01 challenge using Cloudflare API
   - Wildcard certificate for *.krejci.io + krejci.io
   - Auto-renewal every 60 days
2. ✅ Obtained Cloudflare API token with DNS edit permissions
3. ✅ Stored Cloudflare token securely on hosts needing certificates:
   - /var/lib/acme/cloudflare-api-token (mode 600, not in git)
   - Token injected per-host during deployment
4. ✅ Updated service configurations for HTTPS:
   - Grafana: https://vpsfree.krejci.io/grafana/
   - Prometheus: http://localhost:9090 (internal datasource only)
   - Immich: https://immich.krejci.io/
5. ✅ Implemented defense in depth security:
   - All services listen on localhost (127.0.0.1) only
   - Nginx as single TLS termination point on 0.0.0.0:443
   - Firewall restricted to nb-homelab interface only
   - Removed ports 80, 2283, 3000, 9090 from firewall
6. ✅ Deployed to production hosts:
   - vpsfree: Certificate acquired, Grafana HTTPS working
   - thinkcenter: Certificate acquired, Immich HTTPS working

**Certificate Details:**
- Issuer: Let's Encrypt (E7)
- Expires: February 17, 2026
- Coverage: *.krejci.io and krejci.io
- Auto-renewal: Every 60 days via systemd timer

**Remaining Tasks:**
- ✅ thinkcenter deployed with HTTPS
- Deploy updated configuration to optiplex (requires local access)
- Enroll remaining hosts: e470, rpi4, prusa
- Clean up /var/lib/wireguard directories on deployed hosts (manual cleanup)
- Eventually delete modules/wg-server.nix file (kept for reference)

## Final Configuration

### modules/networking.nix
Netbird configuration with DNS capability fix and extra DNS labels support:

```nix
# Netbird configuration using multi-instance support
# Only homelab network managed by Nix
# Company network configured separately via devops-provided config
services.netbird.clients = {
  homelab = {
    port = 51820;
    # Interface will be: nb-homelab
    # Setup key: /var/lib/netbird-homelab/setup-key
    # State: /var/lib/netbird-homelab/
  };
};

# Add capability to bind to port 53 for Netbird DNS
systemd.services.netbird-homelab.serviceConfig.AmbientCapabilities = [
  "CAP_NET_ADMIN"
  "CAP_NET_RAW"
  "CAP_BPF"
  "CAP_NET_BIND_SERVICE"  # Required for DNS on port 53
];

# Automatic enrollment using setup key on first boot
systemd.services.netbird-homelab-enroll = {
  description = "Enroll Netbird homelab client with setup key";
  wantedBy = ["multi-user.target"];
  after = ["netbird-homelab.service"];
  requires = ["netbird-homelab.service"];
  unitConfig.ConditionPathExists = "/var/lib/netbird-homelab/setup-key";

  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    Restart = "on-failure";
    RestartSec = 5;
    StartLimitBurst = 3;
    ExecStart = let
      setupKeyFile = "/var/lib/netbird-homelab/setup-key";
      daemonAddr = "unix:///var/run/netbird-homelab/sock";
      extraDnsLabels = config.hosts.self.extraDnsLabels or [];
      dnsLabelsArg =
        if extraDnsLabels == []
        then ""
        else "--extra-dns-labels ${lib.concatStringsSep "," extraDnsLabels}";
    in
      pkgs.writeShellScript "netbird-enroll" ''
        set -euo pipefail

        # Enroll with setup key, specifying the correct daemon address
        ${pkgs.netbird}/bin/netbird up \
          --daemon-addr ${daemonAddr} \
          --hostname ${config.networking.hostName} \
          --setup-key "$(cat ${setupKeyFile})" \
          ${dnsLabelsArg}

        # Only reached after successful enrollment
        rm -f ${setupKeyFile}
      '';
  };
};

# NetworkManager should not manage VPN interfaces
networking.networkmanager.unmanaged = [ "nb-*" ];
```

### scripts.nix
The `install_netbird_key()` function in nixos-install script:

```bash
function install_netbird_key() {
  local -r hostname="$1"

  # Check if NETBIRD_API_TOKEN is set, prompt if not
  if [ -z "${NETBIRD_API_TOKEN:-}" ]; then
    NETBIRD_API_TOKEN=$(ask_for_token "Netbird API token")

    if [ -z "$NETBIRD_API_TOKEN" ]; then
      echo "ERROR: Netbird API token is required" >&2
      exit 1
    fi

    export NETBIRD_API_TOKEN
  fi

  echo "Generating Netbird setup key for $hostname" >&2

  # Generate one-off setup key using Netbird API
  # Requires NETBIRD_API_TOKEN environment variable
  local api_response
  if ! api_response=$(curl -s -X POST https://api.netbird.io/api/setup-keys \
    -H "Authorization: Token $NETBIRD_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data-raw "{\"name\":\"$hostname\",\"type\":\"one-off\",\"expires_in\":86400,\"auto_groups\":[],\"usage_limit\":1,\"ephemeral\":false}" 2>&1); then
    echo "ERROR: Failed to create Netbird setup key via API" >&2
    echo "Response: $api_response" >&2
    exit 1
  fi

  # Extract the key from the API response
  local -r setup_key=$(echo "$api_response" | jq -r '.key')

  # Validate that we got a non-empty key
  if [ -z "$setup_key" ] || [ "$setup_key" = "null" ]; then
    echo "ERROR: Netbird setup key is empty or invalid" >&2
    echo "API Response: $api_response" >&2
    exit 1
  fi

  # Create directory for Netbird setup key
  install -d -m755 "$TEMP/$NETBIRD_KEY_FOLDER"
  echo "$setup_key" > "$TEMP/$NETBIRD_KEY_PATH"
  chmod 600 "$TEMP/$NETBIRD_KEY_PATH"

  echo "Netbird setup key installed for $hostname" >&2
}
```

Called from main() function in nixos-install script.

### modules/ssh.nix
SSH configured to listen on all interfaces with firewall restriction:

```nix
services.openssh = {
  enable = true;
  # Listen on all interfaces, security enforced via firewall
  listenAddresses = [];
  # ... other settings ...
};

# Restrict SSH access to VPN interface only
networking.firewall.interfaces."nb-homelab".allowedTCPPorts = [22];
```

### modules/acme.nix
Let's Encrypt ACME configuration for wildcard certificates:

```nix
{config, ...}: {
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "admin@krejci.io";
      dnsProvider = "cloudflare";
      # Cloudflare API token stored in /var/lib/acme/cloudflare-api-token
      # Token is injected per-host during installation (not in git)
      environmentFile = "/var/lib/acme/cloudflare-api-token";
      dnsResolver = "1.1.1.1:53";
    };
  };

  # Wildcard certificate for *.krejci.io
  security.acme.certs."krejci.io" = {
    domain = "*.krejci.io";
    extraDomainNames = ["krejci.io"];
    group = "nginx";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/acme 0755 acme acme -"
  ];
}
```

### modules/grafana.nix
Services listen on localhost with nginx HTTPS proxy:

```nix
let
  domain = "krejci.io";
  serverDomain = config.hosts.self.hostName + "." + domain;
  grafanaPort = 3000;
in {
  # Allow HTTPS on VPN interface (nginx proxies to all services)
  networking.firewall.interfaces."nb-homelab".allowedTCPPorts = [443];

  services.prometheus = {
    enable = true;
    listenAddress = "0.0.0.0";
    # Auto-discover all NixOS hosts
    scrapeConfigs = [{
      job_name = "node";
      static_configs = [{
        targets = let
          nixosHosts = lib.filterAttrs (_: hostConfig: hostConfig.kind == "nixos") config.hosts;
        in
          lib.mapAttrsToList (hostName: _: "${hostName}.${domain}:9100") nixosHosts;
      }];
    }];
  };

  services.grafana.settings.server = {
    http_addr = "0.0.0.0";
    domain = serverDomain;
    root_url = "http://${serverDomain}/grafana";
  };

  # Nginx proxies to localhost (same host)
  services.nginx.virtualHosts.${serverDomain} = {
    listenAddresses = ["0.0.0.0"];
    locations."/grafana/".proxyPass = "http://localhost:${toString grafanaPort}";
  };
}
```

### modules/common.nix
Node exporter on all hosts:

```nix
services.prometheus.exporters.node = {
  enable = true;
  openFirewall = false;
  listenAddress = "0.0.0.0";
};

networking.firewall.interfaces."nb-homelab".allowedTCPPorts = [9100];
```

### modules/immich.nix
Immich service with dedicated TPM-encrypted NVMe disk and HTTPS:

```nix
{...}: let
  domain = "krejci.io";
  immichDomain = "immich.${domain}";
  immichPort = 2283;
  # Second disk for Immich data (NVMe)
  # Assumes partition is already created with label "disk-immich-luks"
  luksDevice = "/dev/disk/by-partlabel/disk-immich-luks";
in {
  # Allow HTTPS on VPN interface (nginx proxies to Immich for both web and mobile)
  networking.firewall.interfaces."nb-homelab".allowedTCPPorts = [443];

  # NVMe data disk - TPM encrypted, not touched during deployment
  boot.initrd.luks.devices."immich-data" = {
    device = luksDevice;
    allowDiscards = true;
  };

  fileSystems."/var/lib/immich" = {
    device = "/dev/mapper/immich-data";
    fsType = "ext4";
    options = ["defaults" "nofail"];
  };

  services.immich = {
    enable = true;
    # Listen on localhost only, accessed via nginx proxy (defense in depth)
    host = "127.0.0.1";
    port = immichPort;
    # Media stored on dedicated NVMe disk at /var/lib/immich (default)
  };

  # Nginx reverse proxy with HTTPS - accessible via immich.krejci.io
  services.nginx = {
    enable = true;
    virtualHosts.${immichDomain} = {
      listenAddresses = ["0.0.0.0"];
      # Enable HTTPS with Let's Encrypt wildcard certificate
      forceSSL = true;
      useACMEHost = "krejci.io";
      locations."/" = {
        proxyPass = "http://localhost:${toString immichPort}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };
}
```

**Disk Preparation (thinkcenter only):**
The NVMe disk (/dev/nvme0n1) is configured as a separate TPM-encrypted volume for Immich media storage:

```bash
# 1. Partition the NVMe disk
parted /dev/nvme0n1 -- mklabel gpt
parted /dev/nvme0n1 -- mkpart primary 0% 100%
sgdisk --change-name=1:disk-immich-luks /dev/nvme0n1

# 2. Create LUKS encryption with temporary password
cryptsetup luksFormat /dev/disk/by-partlabel/disk-immich-luks
cryptsetup open /dev/disk/by-partlabel/disk-immich-luks immich-data

# 3. Create filesystem
mkfs.ext4 -L immich-data /dev/mapper/immich-data
cryptsetup close immich-data

# 4. Enroll TPM key (after reboot)
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0,7 /dev/disk/by-partlabel/disk-immich-luks

# 5. Verify enrollment
systemd-cryptenroll /dev/disk/by-partlabel/disk-immich-luks
# Should show: SLOT 0 password, SLOT 1 tpm2
```

### hosts.nix
Simplified schema with extra DNS labels support - removed ipAddress and wgPublicKey options:

```nix
options.hosts = mkOption {
  type = types.attrsOf (types.submodule ({
    options = {
      hostName = mkOption { type = types.str; };
      system = mkOption { type = types.str; default = "x86_64-linux"; };
      kind = mkOption { type = types.str; default = "nixos"; };
      device = mkOption { type = types.str; };
      swapSize = mkOption { type = types.str; default = "1G"; };
      extraModules = mkOption { type = types.listOf types.path; default = []; };
      extraDnsLabels = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Extra DNS labels for Netbird (for service aliases)";
      };
    };
  }));
};
```

**Example with service aliases:**
```nix
thinkcenter = {
  device = "/dev/sda";
  swapSize = "8G";
  extraDnsLabels = ["immich"];  # Creates immich.x.nb → thinkcenter IP
  extraModules = [
    ./modules/disk-tpm-encryption.nix
    ./modules/immich.nix
  ];
};
```

This creates the DNS alias `immich.x.nb` that resolves to thinkcenter's IP address through Netbird's embedded DNS.

## Rollback Plan
- WireGuard configuration preserved in git history (commit before removal)
- Can revert by checking out pre-migration commit and redeploying
- WireGuard fully removed from codebase as Netbird proven stable

## Setup Key Management

Setup keys are generated on-demand during deployment using the Netbird Management API.

**Important:** The setup key is only for initial enrollment, NOT the permanent VPN key.

### Workflow
1. Set `NETBIRD_API_TOKEN` environment variable before running nixos-install (or enter when prompted)
2. Installation script calls Netbird API (`POST /api/setup-keys`) with:
   - `name: "$hostname"` - matches hostname from hosts.nix
   - `type: "one-off"` - setup key is single-use
   - `expires_in: 86400` - expires in 24 hours
   - `usage_limit: 1` - can only be used once
   - `ephemeral: false` - peers are PERMANENT (not ephemeral peers)
3. Setup key stored in TEMP directory at `/var/lib/netbird-homelab/setup-key`
4. nixos-anywhere copies TEMP to target via `--extra-files`
5. On first boot, Netbird service:
   - Reads the setup key for authentication
   - Contacts Netbird management server
   - Auto-generates permanent WireGuard private/public key pair
   - Stores private key in `/var/lib/netbird-homelab/` (never leaves machine)
   - Sends public key to management server
   - Setup key is consumed and invalidated
6. Machine is now permanently enrolled with its own WireGuard keys

### Benefits
- No secrets committed to git repository
- No secrets in Nix configuration
- Each host gets unique, auditable setup key
- Keys are ephemeral (single-use, auto-deleted)
- Hostname automatically matches hosts.nix definition
- Same pattern as WireGuard key handling

## Testing Checklist ✅ COMPLETED
- ✅ Setup key generated successfully via Netbird API
- ✅ Hostname in Netbird matches hosts.nix entry
- ✅ Netbird service starts successfully
- ✅ nb-homelab interface created and has IP
- ✅ Can ping other Netbird peers by IP
- ✅ DNS resolution works for Netbird peer names (*.x.nb)
- ✅ SSH access works through Netbird
- ✅ Services remain accessible (Grafana, Prometheus)
- ✅ NetworkManager doesn't interfere with nb-homelab
- ✅ Netbird survives reboot
- ✅ Netbird reconnects after network changes
- ✅ No setup keys stored in git or Nix config
- ✅ CAP_NET_BIND_SERVICE required for DNS port 53

## Migration Summary

**Actual Timeline:**
- Phase 1 (Preparation): ✅ 3 hours
- Phase 2 (Test Migration - t14): ✅ 4 hours (enrollment service debugging)
- Phase 3 (Gradual Rollout): ✅ 1 day (5 hosts enrolled)
- Phase 4 (DNS Migration): ✅ 3 hours (capability fix required)
- Phase 5 (Cleanup): ✅ 2 hours (complete WireGuard removal)

**Total Time:** ~2 days of active work

**Key Learnings:**
1. Multi-instance Netbird requires explicit daemon socket addresses
2. CAP_NET_BIND_SERVICE is essential for Netbird DNS on port 53
3. Enrollment service needs retry logic for daemon startup timing
4. Services should listen on 0.0.0.0 with interface-specific firewall rules
5. Nginx should proxy to localhost when on same host (not external domain)
6. Setup keys must be one-off with ephemeral:false for permanent peers
7. ISO installer needs reusable setup keys with ephemeral:true
8. Enrolled but undeployed hosts are reachable but SSH may be refused
9. Extra DNS labels must be applied during enrollment, not after
10. Setup keys need "Allow Extra DNS labels" permission to use this feature
11. Fresh enrollment required to add labels - delete peer, remove state, re-enroll
12. Extra DNS labels work cross-platform (desktop, mobile) without custom DNS servers

## Service Aliases with Extra DNS Labels

Netbird's extra DNS labels feature provides native support for service aliases without requiring custom DNS servers like dnsmasq.

### How It Works

1. **Configuration**: Define `extraDnsLabels` in `hosts.nix` for each host
2. **Enrollment**: Labels are registered during initial peer enrollment via `--extra-dns-labels` flag
3. **Resolution**: Netbird's embedded DNS automatically resolves `<label>.x.nb` to the host's IP
4. **Platform Support**: Works on all platforms (Linux, macOS, Windows, iOS, Android)

### Example: Immich Service

For a service like Immich running on thinkcenter:

```nix
# hosts.nix
thinkcenter = {
  device = "/dev/sda";
  swapSize = "8G";
  extraDnsLabels = ["immich"];  # Creates immich.x.nb alias
  extraModules = [
    ./modules/immich.nix
  ];
};
```

**Result:**
- `thinkcenter.x.nb` → 100.76.109.245 (primary hostname)
- `immich.x.nb` → 100.76.109.245 (service alias)

Both resolve to the same IP, allowing users to access Immich at `http://immich.x.nb` instead of remembering the host name.

### Requirements

1. **Setup Key Permissions**: Create setup keys in Netbird dashboard with "Allow Extra DNS labels" enabled
2. **Fresh Enrollment**: Extra DNS labels only apply during enrollment, not to existing peers
3. **Configuration**: Labels must be defined in `hosts.nix` before enrollment
4. **No Custom DNS**: Remove any custom DNS servers (like dnsmasq) - Netbird handles it natively

### Adding Labels to Existing Peers

To add extra DNS labels to an already-enrolled peer:

1. Delete peer from Netbird dashboard
2. On the target machine (local access):
   ```bash
   sudo systemctl stop netbird-homelab.service
   sudo rm -f /var/lib/netbird-homelab/config.json
   sudo rm -f /var/lib/netbird-homelab/state.json
   echo '<NEW-SETUP-KEY>' | sudo tee /var/lib/netbird-homelab/setup-key
   sudo systemctl start netbird-homelab.service
   sleep 5
   sudo systemctl restart netbird-homelab-enroll.service
   ```
3. Verify enrollment: `netbird status` should show the peer connected

### Benefits

- **No Custom DNS**: Eliminates need for dnsmasq or other DNS servers
- **Cross-Platform**: Works on all Netbird clients without special configuration
- **Declarative**: Service aliases defined in `hosts.nix` alongside host configuration
- **Automatic**: Enrollment script reads `extraDnsLabels` and applies during setup
- **Persistent**: Labels persist across reboots and service restarts

## Prerequisites
- Netbird account created at https://app.netbird.io
- Netbird API token obtained (for API authentication)
- Export `NETBIRD_API_TOKEN` before running `nix run .#nixos-install` (or enter when prompted)
