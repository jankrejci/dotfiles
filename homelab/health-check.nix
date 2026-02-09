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
  cfg = config.homelab.healthCheck;
  healthChecks = config.homelab.healthChecks;
  hostname = config.networking.hostName;

  ntfyEndpoint = "${cfg.ntfyUrl}:${toString cfg.ntfyPort}/${cfg.ntfyTopic}";

  mkHealthCheckScript = ntfyTokenPath:
    pkgs.writeShellApplication {
      name = "system-health-check";
      runtimeInputs = [pkgs.coreutils pkgs.curl];
      text = ''
        set -a
        # Path is runtime agenix secret, not available at build time.
        # shellcheck disable=SC1091
        source "${ntfyTokenPath}"
        set +a
        readonly NTFY_TOKEN

        MESSAGE=""
        FAILED=0
        hostname="${hostname}"
        HOSTNAME="''${hostname^}"

        report_result() {
          local name=$1 status=$2
          MESSAGE+="$name $status\n"
        }

        send_notification() {
          local title=$1 message=$2 priority=$3 tags=$4
          printf "%b" "$message" | curl -s -X POST \
            "${ntfyEndpoint}" \
            -H "Authorization: Bearer $NTFY_TOKEN" \
            -H "Title: $title" \
            -H "Priority: $priority" \
            -H "Tags: $tags" \
            --data-binary @-
        }

        # Run each check and report result
        ${lib.concatStringsSep "\n" (map (check: ''
            if timeout ${toString check.timeout} ${lib.getExe check.script}; then
              report_result "${check.name}" "OK"
            else
              report_result "${check.name}" "FAILED"
              FAILED=$((FAILED + 1))
            fi
          '')
          healthChecks)}

        if [ "$FAILED" -eq 0 ]; then
          send_notification "$HOSTNAME OK" "$MESSAGE" "default" "white_check_mark"
        else
          send_notification "$HOSTNAME FAILED" "$MESSAGE" "high" "warning"
        fi
      '';
    };
in {
  options.homelab.healthCheck = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable system health check notifications.";
    };

    ntfyUrl = lib.mkOption {
      type = lib.types.str;
      description = "Ntfy server URL without port.";
    };

    ntfyPort = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = "Ntfy server port.";
    };

    ntfyTopic = lib.mkOption {
      type = lib.types.str;
      description = "Ntfy topic for health check notifications.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ntfy token for health check notifications
    age.secrets.ntfy-token-env = {
      rekeyFile = ../secrets/ntfy-token-env.age;
    };

    systemd.services.system-health-check = {
      description = "System health check with ntfy notification";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = lib.getExe (mkHealthCheckScript config.age.secrets.ntfy-token-env.path);
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
