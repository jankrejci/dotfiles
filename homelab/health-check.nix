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
  global = config.homelab.global;
  hostName = config.homelab.host.hostName;
  ntfyTopic = "system-health";

  # Ntfy token file path
  secretsDir = "/var/lib/health-check/secrets";
  ntfyTokenPath = "${secretsDir}/ntfy-token";

  # Handler for writing ntfy token to health-check secrets directory
  ntfySecretHandler = pkgs.writeShellApplication {
    name = "health-check-ntfy-handler";
    text = ''
      install -d -m 700 -o root -g root ${secretsDir}
      token=$(cat)
      # Escape single quotes for shell sourcing
      sq="'"
      escaped_token=$(printf '%s' "$token" | sed "s/$sq/$sq\\\\$sq$sq/g")
      printf 'NTFY_TOKEN=%s%s%s\n' "$sq" "$escaped_token" "$sq" > ${ntfyTokenPath}
      chmod 600 ${ntfyTokenPath}
    '';
  };

  healthCheckScript = pkgs.writeShellApplication {
    name = "system-health-check";
    runtimeInputs = [pkgs.coreutils pkgs.curl];
    text = ''
      NTFY_TOKEN_PATH="${ntfyTokenPath}"
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
          "https://ntfy.${global.domain}/${ntfyTopic}" \
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
        send_notification "${hostName} OK" "All services healthy" "default" "white_check_mark"
      else
        send_notification "${hostName} Attention Required" "$MESSAGE" "high" "warning"
      fi
    '';
  };
in {
  config = lib.mkIf (healthChecks != []) {
    # Declare ntfy token secret for health check notifications
    homelab.secrets.health-check-ntfy = {
      generate = "token";
      handler = ntfySecretHandler;
      username = "health-check";
      register = "ntfy";
    };

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
