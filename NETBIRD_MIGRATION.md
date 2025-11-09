# Netbird Migration Plan

## Current State
- Manual WireGuard mesh VPN with vpsfree (192.168.99.1) as central hub
- 192.168.99.0/24 network with static peer configurations
- CoreDNS on vpsfree providing *.vpn domain resolution
- All hosts have WireGuard peer configs pointing to vpsfree:51820
- Netbird service enabled but not configured

## Target State
- Netbird mesh VPN using hosted management service
- Netbird's built-in DNS for peer name resolution
- Remove manual WireGuard configuration
- Simplified peer management through Netbird dashboard

## Migration Steps

### Phase 1: Preparation
1. ✅ Create Netbird account at https://app.netbird.io
2. Obtain Netbird API token for CLI automation (for generating setup keys)
3. Update `modules/networking.nix` with Netbird configuration
4. Update `scripts.nix` nixos-install function to:
   - Add `install_netbird_key()` function (similar to `install_wg_key()`)
   - Use Netbird CLI to generate ephemeral setup key with hostname
   - Store setup key in TEMP directory (like WireGuard key)
   - Pass to target via nixos-anywhere --extra-files

### Phase 2: Test Migration (t14)
1. Run `nix run .#nixos-install t14`:
   - Script generates ephemeral Netbird setup key via CLI (name="t14")
   - Setup key stored in TEMP directory at /var/lib/netbird-homelab/setup-key
   - nixos-anywhere copies TEMP to target via --extra-files
   - Netbird homelab service reads setup key on first boot and enrolls
2. Verify Netbird connectivity (nb-homelab interface comes up)
3. Test DNS resolution through Netbird
4. Verify can reach other services via both wg0 and nb-homelab
5. Confirm hostname in Netbird dashboard shows "t14"
6. Note: Netbird IP will differ from 192.168.99.24 (100.64.0.0/10 range)
7. Keep WireGuard running as fallback until all hosts migrated

### Phase 3: Gradual Rollout
1. Enroll hosts one by one using deployment script:
   - First: t14 (test migration)
   - Desktop hosts: thinkpad, optiplex, framework
   - Server hosts: thinkcenter
   - Raspberry Pi hosts: rpi4, prusa
   - Non-NixOS hosts: nokia (manual enrollment)
2. For each host:
   - Script generates setup key via Netbird CLI with matching hostname
   - Setup key injected during deployment
   - Verify hostname in Netbird matches hosts.nix
   - Note IP address assigned by Netbird (may differ from hosts.nix)
3. Test inter-host connectivity after each addition

### Phase 4: DNS Migration
1. Configure Netbird DNS in dashboard:
   - Enable nameserver groups
   - Set up *.vpn domain resolution via Netbird
   - Configure DNS for each enrolled peer
2. Test DNS resolution from enrolled hosts
3. Verify service discovery works through Netbird DNS

### Phase 5: Cleanup
1. Once all hosts enrolled and stable:
   - Remove WireGuard peer configurations from networking.nix
   - Remove wg-server.nix from vpsfree
   - Remove CoreDNS configuration
   - Remove WireGuard firewall rules
   - Clean up /var/lib/wireguard directories
   - Remove wgPublicKey from hosts.nix schema
   - Remove hosts/*/wg-key.pub files
2. Update NetworkManager config (wg0 → wt0)
3. Update any hardcoded WireGuard references

## Configuration Changes

### Modified: modules/networking.nix
Configuration lives directly in networking.nix (no separate module):

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

# NetworkManager should not manage VPN interfaces
# Include nb-* pattern to cover both homelab and any manually configured networks
networking.networkmanager.unmanaged = [ "wg0" "nb-*" ];
```

Changes needed:
- Replace `services.netbird.enable = true` with `services.netbird.clients.homelab`
- Update NetworkManager.unmanaged to include Netbird interfaces
- Keep WireGuard configuration during migration (remove in Phase 5)
- Keep all other networking config unchanged

### Modified: scripts.nix
Add `install_netbird_key()` function to nixos-install script:

```bash
function install_netbird_key() {
  local -r hostname="$1"

  echo "Generating Netbird setup key for $hostname (homelab network)..." >&2

  # Generate ephemeral setup key using Netbird CLI
  # Requires NETBIRD_API_TOKEN environment variable for homelab account
  local -r setup_key=$(netbird setup-key create \
    --name "$hostname" \
    --ephemeral \
    --auto-approve \
    --output-format json | jq -r '.key')

  # Create directory for Netbird setup key
  # Path matches multi-instance structure: /var/lib/netbird-homelab/
  local -r netbird_key_folder="/var/lib/netbird-homelab"
  install -d -m755 "$TEMP/$netbird_key_folder"
  echo "$setup_key" > "$TEMP/$netbird_key_folder/setup-key"
  chmod 600 "$TEMP/$netbird_key_folder/setup-key"

  echo "Netbird setup key installed for $hostname (homelab)" >&2
}
```

Call from main() function:
```bash
install_wg_key "$hostname"
install_netbird_key "$hostname"  # Add this line
```

Notes:
- Only homelab network managed through Nix configuration
- Company network can be configured separately (e.g., via devops-provided config file)
- Both networks can run simultaneously without conflicts

### Modified: hosts.nix
- Eventually remove wgPublicKey option from host schema
- IP addresses will differ (Netbird assigns from 100.64.0.0/10 CGNAT range)
- Keep ipAddress field for WireGuard during migration, remove after cleanup
- Hostnames remain authoritative source of truth (match Netbird peer names)

### Remove: modules/wg-server.nix
- Remove from vpsfree extraModules in hosts.nix
- CoreDNS no longer needed for VPN DNS
- WireGuard peer management handled by Netbird

## Rollback Plan
- Keep WireGuard configuration in git history
- Can revert to WireGuard by checking out previous commit
- During migration, both WireGuard and Netbird can coexist
- Remove WireGuard only after Netbird proven stable

## Setup Key Management

Setup keys are generated on-demand during deployment using Netbird CLI.

**Important:** The setup key is only for initial enrollment, NOT the permanent VPN key.

### Workflow
1. Set `NETBIRD_API_TOKEN` environment variable before running nixos-install
2. Installation script calls `netbird setup-key create` with:
   - `--name "$hostname"` - matches hostname from hosts.nix
   - `--ephemeral` - setup key is single-use (deleted after enrollment)
   - `--auto-approve` - no manual approval needed
   - Note: This creates an ephemeral setup key, but peers are PERMANENT (not ephemeral peers)
3. Setup key stored in TEMP directory at `/var/lib/netbird-homelab/setup-key`
4. nixos-anywhere copies TEMP to target via `--extra-files`
5. On first boot, Netbird service:
   - Reads the setup key for authentication
   - Contacts Netbird management server
   - Auto-generates permanent WireGuard private/public key pair
   - Stores private key in `/var/lib/netbird-homelab/` (never leaves machine)
   - Sends public key to management server
   - Deletes the setup key (ephemeral)
6. Machine is now permanently enrolled with its own WireGuard keys

### Benefits
- No secrets committed to git repository
- No secrets in Nix configuration
- Each host gets unique, auditable setup key
- Keys are ephemeral (single-use, auto-deleted)
- Hostname automatically matches hosts.nix definition
- Same pattern as WireGuard key handling

## Testing Checklist
- [ ] Setup key generated successfully via Netbird CLI
- [ ] Hostname in Netbird matches hosts.nix entry
- [ ] Netbird service starts successfully
- [ ] wt0 interface created and has IP
- [ ] Can ping other Netbird peers by IP
- [ ] DNS resolution works for Netbird peer names
- [ ] SSH access works through Netbird
- [ ] Services remain accessible (grafana, etc.)
- [ ] NetworkManager doesn't interfere with wt0
- [ ] Netbird survives reboot
- [ ] Netbird reconnects after network changes
- [ ] No setup keys stored in git or Nix config

## Timeline Estimate
- Phase 1 (Preparation): 2-3 hours (update scripts.nix and networking.nix)
- Phase 2 (Test Migration - t14): 2-4 hours (includes testing and troubleshooting)
- Phase 3 (Gradual Rollout): 1-2 days (stagger deployments for safety)
- Phase 4 (DNS Migration): 2-4 hours (configure Netbird DNS)
- Phase 5 (Cleanup): 1-2 hours (remove WireGuard config)

Total: 3-5 days with conservative testing between phases

## Prerequisites
- Netbird account created at https://app.netbird.io
- Netbird API token obtained (for CLI authentication)
- `netbird` CLI tool available in deployment environment
- Export `NETBIRD_API_TOKEN` before running `nix run .#nixos-install`
