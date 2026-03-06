# Monitor network connectivity and dump diagnostics on failure
#
# - pings 1.1.1.1 and 8.8.8.8 to detect outages
# - tests TCP via HTTP HEAD to detect non-ICMP failures
# - checks DNS resolution via resolvectl
# - auto-detects interfaces from default routes
# - dumps full diagnostics when any non-ping check fails
# - usage: nix run .#network-monitor [-- [--log PATH] [INTERVAL]]
{
  pkgs,
  lib,
}:
pkgs.writeShellApplication {
  name = "network-monitor";
  runtimeInputs = with pkgs; [
    coreutils
    curl
    iproute2
    iputils
    systemd
    gnugrep
    gawk
  ];
  text = ''
    # shellcheck source=/dev/null
    source ${lib}

    readonly DEFAULT_INTERVAL=15
    readonly DEFAULT_LOG="/tmp/network-monitor.log"
    readonly PING_TARGETS=("1.1.1.1" "8.8.8.8")
    readonly DNS_TARGET="google.com"
    # HTTP target for TCP connectivity check
    readonly HTTP_TARGET="http://detectportal.firefox.com/canonical.html"

    function usage() {
      info "Usage: network-monitor [--log PATH] [INTERVAL]"
      info "  --log PATH   Log file path (default: $DEFAULT_LOG)"
      info "  INTERVAL     Seconds between checks (default: $DEFAULT_INTERVAL)"
      exit 1
    }

    function parse_args() {
      LOG_FILE="$DEFAULT_LOG"
      INTERVAL="$DEFAULT_INTERVAL"

      while [ $# -gt 0 ]; do
        case "$1" in
          --log)
            [ $# -ge 2 ] || { error "--log requires a path argument"; usage; }
            LOG_FILE="$2"
            shift 2
            ;;
          --help|-h)
            usage
            ;;
          *)
            # Positional arg is interval
            if [[ "$1" =~ ^[0-9]+$ ]]; then
              INTERVAL="$1"
              shift
            else
              error "Unknown argument: $1"
              usage
            fi
            ;;
        esac
      done

      export LOG_FILE INTERVAL
    }

    # Write to both stderr and log file
    function log() {
      local -r msg="$*"
      echo "$msg" >&2
      echo "$msg" >> "$LOG_FILE"
    }

    # Check ping reachability. Returns 0 on success, 1 on failure.
    function check_ping() {
      local -r target="$1"
      ping -c 1 -W 3 "$target" > /dev/null 2>&1
    }

    # Check TCP connectivity via HTTP HEAD request. Returns 0 on success, 1 on failure.
    function check_http() {
      curl -sf --head --max-time 5 "$HTTP_TARGET" > /dev/null 2>&1
    }

    # Check DNS resolution via resolvectl. Returns 0 on success, 1 on failure.
    function check_dns() {
      resolvectl query "$DNS_TARGET" > /dev/null 2>&1
    }

    # Get default gateway interfaces from routing table
    function get_default_interfaces() {
      ip route show default | gawk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | sort -u
    }

    # Get default gateway IPs from routing table
    function get_default_gateways() {
      ip route show default | gawk '{for(i=1;i<=NF;i++) if($i=="via") print $(i+1)}' | sort -u
    }

    function dump_diagnostics() {
      log ""
      log "=== DIAGNOSTIC DUMP ==="

      log ""
      log "-- Interface states and IPs --"
      ip -brief address 2>&1 | while IFS= read -r line; do log "  $line"; done

      log ""
      log "-- Default routes --"
      ip route show default 2>&1 | while IFS= read -r line; do log "  $line"; done

      log ""
      log "-- Full route table --"
      ip route 2>&1 | while IFS= read -r line; do log "  $line"; done

      log ""
      log "-- NetworkManager device status --"
      if command -v nmcli &>/dev/null && nmcli general status &>/dev/null; then
        nmcli device status 2>&1 | while IFS= read -r line; do log "  $line"; done
      else
        log "  NetworkManager not running"
      fi

      log ""
      log "-- ARP neighbor table --"
      local gateways
      gateways=$(get_default_gateways)
      if [ -n "$gateways" ]; then
        while IFS= read -r gw; do
          ip neighbor show "$gw" 2>&1 | while IFS= read -r line; do log "  $line"; done
        done <<< "$gateways"
      else
        log "  No default gateways found"
        ip neighbor show 2>&1 | while IFS= read -r line; do log "  $line"; done
      fi

      log ""
      log "-- Network service journal (last 20 lines) --"
      if systemctl is-active --quiet NetworkManager; then
        journalctl -u NetworkManager --no-pager -n 20 --no-hostname 2>&1 | while IFS= read -r line; do log "  $line"; done
      else
        journalctl -u systemd-networkd --no-pager -n 20 --no-hostname 2>&1 | while IFS= read -r line; do log "  $line"; done
      fi

      log "=== END DIAGNOSTIC DUMP ==="
      log ""
    }

    function run_checks() {
      local -r timestamp=$(date -Iseconds)
      local failed=0
      local ping_only=true
      local results=""

      # Internet ping checks
      for target in "''${PING_TARGETS[@]}"; do
        if check_ping "$target"; then
          results+=" ping=$target:ok"
        else
          results+=" ping=$target:FAIL"
          failed=1
        fi
      done

      # HTTP TCP check
      if check_http; then
        results+=" http:ok"
      else
        results+=" http:FAIL"
        failed=1
        ping_only=false
      fi

      # DNS check
      if check_dns; then
        results+=" dns:ok"
      else
        results+=" dns:FAIL"
        failed=1
        ping_only=false
      fi

      # Interface and gateway summary
      local ifaces gw_summary
      ifaces=$(get_default_interfaces | tr '\n' ',')
      gw_summary=$(get_default_gateways | tr '\n' ',')
      ifaces="''${ifaces%,}"
      gw_summary="''${gw_summary%,}"
      results+=" ifaces=''${ifaces:-none} gw=''${gw_summary:-none}"

      local -r status_line="$timestamp$results"
      log "$status_line"

      # Only dump diagnostics for real outages, not just ICMP being filtered
      if [ "$failed" -eq 1 ] && [ "$ping_only" = false ]; then
        dump_diagnostics
      fi

      return "$failed"
    }

    function main() {
      parse_args "$@"

      info "Network monitor started"
      info "  Interval: ''${INTERVAL}s"
      info "  Log file: $LOG_FILE"
      info "  Ping targets: ''${PING_TARGETS[*]}"
      info "  HTTP target: $HTTP_TARGET"
      info "  DNS target: $DNS_TARGET"
      info "  Press Ctrl-C to stop"
      echo "" >> "$LOG_FILE"
      log "=== Monitor started at $(date -Iseconds) ==="

      # Run until interrupted
      while true; do
        run_checks || true
        sleep "$INTERVAL"
      done
    }

    main "$@"
  '';
}
