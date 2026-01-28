# Re-enroll Netbird with new setup key
#
# - generates fresh setup key via Netbird API
# - injects key to target host via SSH
# - triggers netbird-homelab-enroll service
# - usage: nix run .#reenroll-netbird hostname
{
  pkgs,
  lib,
}:
pkgs.writeShellApplication {
  name = "reenroll-netbird";
  runtimeInputs = with pkgs; [
    coreutils
    openssh
    curl
    jq
  ];
  text = ''
    # shellcheck source=/dev/null
    source ${lib}

    readonly DOMAIN="nb.krejci.io"
    readonly NETBIRD_KEY_PATH="/var/lib/netbird-homelab/setup-key"

    function prepare_peer_removal() {
      local -r hostname="$1"

      info "NEXT STEPS:"
      info "1. Open Netbird dashboard and find peer '$hostname'"
      info "2. When ready, press Enter to trigger enrollment"
      info "3. You will have 60 seconds to remove the old peer"
      info "4. Connection will be lost after triggering"
      read -r -p "Press Enter when ready to trigger enrollment..." _
    }

    function trigger_enrollment() {
      local -r target="$1"
      local -r hostname="$2"

      info "Triggering enrollment service"

      # Try to trigger enrollment - may fail if connection is already lost
      if ! ssh "$target" "sudo systemd-run --on-active=60 systemctl start netbird-homelab-enroll.service" 2>/dev/null; then
        warn "Could not trigger enrollment via SSH (connection may be lost)"
        info "The enrollment service should start automatically on next boot"
        read -r -p "Press Enter to continue..." _
        return 0
      fi

      info "Enrollment scheduled to start in 60 seconds"
      warn "Remove old peer '$hostname' from dashboard NOW"
      read -r -p "Press Enter after removing peer..." _
    }

    function wait_for_host() {
      local -r target="$1"

      info "Waiting for host to come back online (up to 2 minutes)"

      local attempts=0
      local max_attempts=60  # 2 minutes total

      while [ $attempts -lt $max_attempts ]; do
        if ssh -o ConnectTimeout=2 -o BatchMode=yes "$target" "exit" 2>/dev/null; then
          info "Host is back online"
          return 0
        fi

        attempts=$((attempts + 1))

        # Show elapsed time every 10 attempts, otherwise show dot
        local progress="."
        if [ $((attempts % 10)) -eq 0 ]; then
          progress=" $((attempts * 2))s"
        fi
        echo -n "$progress" >&2

        sleep 2
      done

      error "Host did not come back online within $((max_attempts * 2)) seconds"
      info "Check the host's console or Netbird dashboard to verify enrollment status"
      return 1
    }

    function main() {
      local -r hostname=$(require_and_validate_hostname "$@")
      local -r target="admin@$hostname.$DOMAIN"

      require_ssh_reachable "$target"

      local -r setup_key=$(generate_netbird_key "$hostname")
      inject_secret \
        --target "$target" \
        --path "$NETBIRD_KEY_PATH" \
        --content "$setup_key"
      prepare_peer_removal "$hostname"
      trigger_enrollment "$target" "$hostname"
      wait_for_host "$target"

      info "Re-enrollment complete. Verify new peer in dashboard."
    }

    main "$@"
  '';
}
