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
2. ✅ Obtain Netbird API token for CLI automation (for generating setup keys)
3. ✅ Update `modules/networking.nix` with Netbird configuration
4. ✅ Update `scripts.nix` nixos-install function to:
   - Add `install_netbird_key()` function (similar to `install_wg_key()`)
   - Use Netbird API to generate one-off setup key with hostname
   - Store setup key in TEMP directory (like WireGuard key)
   - Pass to target via nixos-anywhere --extra-files

### Phase 2: Test Migration (t14)
1. ✅ Run `nix run .#nixos-install t14`:
   - Script generates one-off Netbird setup key via API (name="t14")
   - Setup key stored in TEMP directory at /var/lib/netbird-homelab/setup-key
   - nixos-anywhere copies TEMP to target via --extra-files
   - Netbird homelab service reads setup key on first boot and enrolls
2. ✅ Verify Netbird connectivity (nb-homelab interface comes up)
3. ⏭️ Test DNS resolution through Netbird (deferred to Phase 4)
4. ✅ Verify can reach other services via both wg0 and nb-homelab
5. ✅ Confirm hostname in Netbird dashboard shows "t14-144-136"
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

### Phase 3: Gradual Rollout
1. Enroll hosts one by one using deployment script:
   - First: t14 (test migration)
   - Desktop hosts: thinkpad, optiplex, framework
   - Server hosts: thinkcenter
   - Raspberry Pi hosts: rpi4, prusa
   - Non-NixOS hosts: nokia (manual enrollment)
2. For each host:
   - Script generates setup key via Netbird API with matching hostname
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

## Testing Checklist
- [ ] Setup key generated successfully via Netbird API
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
- Netbird API token obtained (for API authentication)
- Export `NETBIRD_API_TOKEN` before running `nix run .#nixos-install` (or enter when prompted)
