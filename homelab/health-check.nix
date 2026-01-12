# System health check service
#
# Distributed registry pattern: each service module registers checks via
# homelab.healthChecks option. This module iterates all registered checks
# and sends results to ntfy as a daily notification at 08:00.
#
# Check structure:
#   { name = "Service"; script = writeShellApplication {...}; timeout = 10; }
#
# Testing:
#   systemctl start system-health-check  # run manually
#   journalctl -u system-health-check    # view results
{
  config,
  pkgs,
  lib,
  ...
}: let
  healthChecks = config.homelab.healthChecks;
  ntfyPort = config.homelab.ntfy.port;
  ntfyTopic = "system-health";

  healthCheckScript = pkgs.writeShellApplication {
    name = "system-health-check";
    runtimeInputs = [pkgs.coreutils pkgs.curl];
    text = ''
      NTFY_TOKEN_PATH="/var/lib/health-check/secrets/ntfy-token-env"
      readonly NTFY_TOKEN_PATH

      [ -f "$NTFY_TOKEN_PATH" ] || {
        echo "ERROR: ntfy token file not found"
        exit 1
      }

      set -a
      # shellcheck disable=SC1090
      source "$NTFY_TOKEN_PATH"
      set +a
      readonly NTFY_TOKEN

      MESSAGE=""
      FAILED=0

      report_failure() {
        MESSAGE+="$1\n"
        FAILED=$((FAILED + 1))
      }

      send_notification() {
        local title=$1 message=$2 priority=$3 tags=$4
        printf "%b" "$message" | curl -s -X POST \
          "http://127.0.0.1:${toString ntfyPort}/${ntfyTopic}" \
          -H "Authorization: Bearer $NTFY_TOKEN" \
          -H "Title: $title" \
          -H "Priority: $priority" \
          -H "Tags: $tags" \
          --data-binary @-
      }

      # Run each check
      ${lib.concatStringsSep "\n" (map (check: ''
          timeout ${toString check.timeout} ${lib.getExe check.script} || report_failure "${check.name}"
        '')
        healthChecks)}

      if [ "$FAILED" -eq 0 ]; then
        send_notification "All OK" "All services healthy" "default" "white_check_mark"
      else
        send_notification "Attention Required" "$MESSAGE" "high" "warning"
      fi
    '';
  };
in {
  config = lib.mkIf (healthChecks != []) {
    systemd.tmpfiles.rules = [
      "d /var/lib/health-check/secrets 0700 root root -"
    ];

    systemd.services.system-health-check = {
      description = "System health check with ntfy notification";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = lib.getExe healthCheckScript;
      };
    };

    systemd.timers.system-health-check = {
      description = "Daily system health check timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "08:00";
        Persistent = true;
        Unit = "system-health-check.service";
      };
    };
  };
}
