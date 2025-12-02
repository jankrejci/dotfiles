{
  config,
  pkgs,
  ...
}: let
  domain = "krejci.io";
  ntfyDomain = "ntfy.${domain}";
  ntfyTopic = "system-health";

  healthCheckScript = pkgs.writeShellApplication {
    name = "system-health-check";
    runtimeInputs = with pkgs; [systemd coreutils curl gawk wireguard-tools iproute2 iputils];
    text = ''
      NTFY_TOKEN_PATH="/var/lib/health-check/secrets/ntfy-token-env"
      readonly NTFY_TOKEN_PATH

      [ -f "$NTFY_TOKEN_PATH" ] || {
        echo "ERROR: ntfy token file not found at $NTFY_TOKEN_PATH"
        exit 1
      }

      # Source environment file to get NTFY_TOKEN
      set -a
      # shellcheck disable=SC1090 # path is validated above
      source "$NTFY_TOKEN_PATH"
      set +a
      readonly NTFY_TOKEN

      MESSAGE=""

      push_message() {
        MESSAGE+="$1\n"
      }

      check_service() {
        local service=$1
        local name=$2
        systemctl is-active --quiet "$service" || {
          push_message "❌ $name"
        }
        return 0
      }

      check_host() {
        local name=$1
        local ip=$2
        ping -c 1 -W 2 "$ip" > /dev/null 2>&1 || {
          push_message "❌ $name"
        }
        return 0
      }

      check_wireguard() {
        local interface=$1
        local max_handshake_age=180

        ip link show "$interface" > /dev/null 2>&1 || {
          push_message "❌ WireGuard"
          return 0
        }

        handshake=$(wg show "$interface" latest-handshakes | awk '{print $2}')
        if [ -z "$handshake" ] || [ "$handshake" = "0" ]; then
          return 0
        fi

        current_time=$(date +%s)
        age=$((current_time - handshake))
        if [ "$age" -gt "$max_handshake_age" ]; then
          push_message "❌ WireGuard stale ($age s)"
        fi
        return 0
      }

      check_borg_backup() {
        local job=$1
        local name=$2
        local max_age_hours=48

        systemctl is-enabled --quiet "borgbackup-job-$job.timer" || {
          push_message "❌ Backup $name disabled"
          return 0
        }

        last_run=$(systemctl show "borgbackup-job-$job.service" -p ActiveEnterTimestamp --value)
        if [ -z "$last_run" ] || [ "$last_run" = "n/a" ]; then
          return 0
        fi

        last_run_epoch=$(date -d "$last_run" +%s 2>/dev/null || echo "0")
        if [ "$last_run_epoch" = "0" ]; then
          return 0
        fi

        current_epoch=$(date +%s)
        age_hours=$(( (current_epoch - last_run_epoch) / 3600 ))

        if [ "$age_hours" -gt "$max_age_hours" ]; then
          push_message "❌ Backup $name ($age_hours h)"
        fi
        return 0
      }

      send_notification() {
        local title=$1
        local message=$2
        local priority=$3
        local tags=$4

        printf "%b" "$message" | curl -s -X POST "https://${ntfyDomain}/${ntfyTopic}" \
          -H "Authorization: Bearer $NTFY_TOKEN" \
          -H "Title: $title" \
          -H "Priority: $priority" \
          -H "Tags: $tags" \
          --data-binary @-
      }

      main() {
        check_host "vpsfree" "10.100.0.2"
        check_wireguard "wg0"

        local services=(
          "immich-server.service:Immich"
          "immich-machine-learning.service:Immich ML"
          "postgresql.service:PostgreSQL"
          "redis-immich.service:Redis"
          "nginx.service:Nginx"
          "prometheus.service:Prometheus"
          "grafana.service:Grafana"
          "ntfy-sh.service:Ntfy"
          "jellyfin.service:Jellyfin"
          "acme-krejci.io.service:ACME"
        )

        for entry in "''${services[@]}"; do
          IFS=':' read -r service name <<< "$entry"
          check_service "$service" "$name"
        done

        check_borg_backup "immich-remote" "remote"
        check_borg_backup "immich-local" "local"

        if [ -z "$MESSAGE" ]; then
          send_notification "All OK" "All services healthy" "default" "white_check_mark"
          exit 0
        fi

        send_notification "Attention Required" "$MESSAGE" "high" "warning"
        exit 0
      }

      main
    '';
  };
in {
  # Create directory for secrets
  systemd.tmpfiles.rules = [
    "d /var/lib/health-check/secrets 0700 root root -"
  ];

  # Systemd service
  systemd.services.system-health-check = {
    description = "System health check with ntfy notification";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = "${pkgs.lib.getExe healthCheckScript}";
    };
  };

  # Systemd timer - runs daily at 8:00 AM
  systemd.timers.system-health-check = {
    description = "Daily system health check timer";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "08:00";
      Persistent = true;
      Unit = "system-health-check.service";
    };
  };
}
