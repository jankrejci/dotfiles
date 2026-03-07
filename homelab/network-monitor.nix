# Network connectivity monitoring
#
# Detects outages that survive network downtime by logging to journal and
# writing textfile collector metrics. Complements Prometheus scrapers which
# only work when network is up.
#
# Components:
# - Local systemd service: check loop every N seconds, writes .prom metrics
# - smokeping_prober: latency histograms and packet loss
# - unbound_exporter: DNS resolver cache and query metrics
# - node_exporter wifi collector: signal, retries, beacon loss
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.network-monitor;
  metricsDir = "/var/lib/prometheus-node-exporter";

  monitorScript = pkgs.writeShellApplication {
    name = "network-monitor-service";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      iproute2
      iputils
      systemd
      gnugrep
      gawk
      bc
      iw
      wireguard-tools
    ];
    text = ''
      readonly PING_TARGETS=(${lib.concatMapStringsSep " " (t: ''"${t}"'') cfg.pingTargets})
      readonly DNS_TARGETS=(${lib.concatMapStringsSep " " (t: ''"${t}"'') cfg.dnsTargets})
      readonly HTTP_TARGET="${cfg.httpTarget}"
      readonly INTERVAL="${toString cfg.interval}"
      readonly PROM_FILE="${metricsDir}/network-monitor.prom"
      readonly WIFI_ENABLED="${lib.boolToString cfg.wifi.enable}"

      # Get default gateway IPs from routing table
      function get_default_gateways() {
        ip route show default | gawk '{for(i=1;i<=NF;i++) if($i=="via") print $(i+1)}' | sort -u
      }

      # Get default gateway interfaces from routing table
      function get_default_interfaces() {
        ip route show default | gawk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | sort -u
      }

      # Check ping reachability with latency measurement
      function check_ping() {
        local -r target="$1"
        local output
        output=$(ping -c 1 -W 3 "$target" 2>/dev/null) || return 1
        # Extract latency from rtt summary line, convert ms to seconds
        echo "$output" | gawk -F'[=/]' '/^rtt/{print $5/1000; exit}'
      }

      # Check DNS resolution with latency
      function check_dns() {
        local -r target="$1"
        local start end
        start=$(date +%s%N)
        resolvectl query "$target" > /dev/null 2>&1 || return 1
        end=$(date +%s%N)
        echo "scale=6; ($end - $start) / 1000000000" | bc -l 2>/dev/null || true
      }

      # Check HTTP connectivity with latency
      function check_http() {
        local time_total
        time_total=$(curl -sf --head --max-time 5 -o /dev/null -w '%{time_total}' "$HTTP_TARGET" 2>/dev/null) || return 1
        echo "$time_total"
      }

      # Dump diagnostics to journal on failure
      function dump_diagnostics() {
        echo "=== DIAGNOSTIC DUMP ==="

        echo "-- Interface states and IPs --"
        ip -brief address 2>&1

        echo "-- Default routes --"
        ip route show default 2>&1

        echo "-- Full route table --"
        ip route 2>&1

        echo "-- ARP neighbor table --"
        local gateways
        gateways=$(get_default_gateways)
        if [ -n "$gateways" ]; then
          while IFS= read -r gw; do
            ip neighbor show "$gw" 2>&1
          done <<< "$gateways"
        else
          echo "No default gateways found"
          ip neighbor show 2>&1
        fi

        echo "-- Network service journal (last 20 lines) --"
        if systemctl is-active --quiet NetworkManager 2>/dev/null; then
          journalctl -u NetworkManager --no-pager -n 20 --no-hostname 2>&1
        else
          journalctl -u systemd-networkd --no-pager -n 20 --no-hostname 2>&1
        fi

        echo "-- iwd station info --"
        if command -v iwctl &>/dev/null; then
          iwctl station list 2>&1 || true
        fi

        echo "=== END DIAGNOSTIC DUMP ==="
      }

      # Collect WiFi metrics from iw station dump
      function collect_wifi() {
        [ "$WIFI_ENABLED" = "true" ] || return 0

        local iface
        iface=$(iw dev 2>/dev/null | gawk '/Interface/{print $2; exit}')
        [ -n "$iface" ] || return 0

        local dump
        dump=$(iw dev "$iface" station dump 2>/dev/null) || return 0
        [ -n "$dump" ] || return 0

        local signal signal_avg tx_retries bssid
        signal=$(echo "$dump" | gawk '/signal:/{print $2; exit}')
        signal_avg=$(echo "$dump" | gawk '/signal avg:/{print $3; exit}')
        tx_retries=$(echo "$dump" | gawk '/tx retries:/{print $3; exit}')
        bssid=$(echo "$dump" | gawk '/Station/{print $2; exit}')

        [ -n "$signal" ] && echo "network_monitor_wifi_signal_dbm{interface=\"$iface\",bssid=\"$bssid\"} $signal"
        [ -n "$signal_avg" ] && echo "network_monitor_wifi_signal_avg_dbm{interface=\"$iface\"} $signal_avg"
        [ -n "$tx_retries" ] && echo "network_monitor_wifi_tx_retries_total{interface=\"$iface\"} $tx_retries"
      }

      # Collect VPN status metrics
      function collect_vpn() {
        # Check netbird if available
        if command -v netbird &>/dev/null; then
          local nb_status
          nb_status=$(netbird status 2>/dev/null) || true
          if echo "$nb_status" | grep -q "Connected"; then
            echo 'network_monitor_vpn_up{tunnel="netbird"} 1'
          else
            echo 'network_monitor_vpn_up{tunnel="netbird"} 0'
          fi
        fi

        # Check wireguard interfaces. A tunnel is up if any peer has a
        # recent handshake. Netbird creates stub peers with handshake 0
        # for idle relay connections, so we find the most recent one.
        local wg_ifaces
        wg_ifaces=$(wg show interfaces 2>/dev/null) || true
        for iface in $wg_ifaces; do
          local latest=0
          while read -r _ ts; do
            [ "$ts" -gt "$latest" ] 2>/dev/null && latest="$ts"
          done < <(wg show "$iface" latest-handshakes 2>/dev/null)
          if [ "$latest" -gt 0 ]; then
            local now age
            now=$(date +%s)
            age=$((now - latest))
            echo "network_monitor_vpn_up{tunnel=\"$iface\"} 1"
            echo "network_monitor_vpn_handshake_age_seconds{tunnel=\"$iface\"} $age"
          else
            echo "network_monitor_vpn_up{tunnel=\"$iface\"} 0"
          fi
        done
      }

      function run_checks() {
        local prom_lines=()
        local any_failure=0
        local infra_failure=false
        local summary=""

        # Gateway ping check
        local gateways
        gateways=$(get_default_gateways | head -1)
        if [ -n "$gateways" ]; then
          local gw_latency
          if gw_latency=$(check_ping "$gateways"); then
            prom_lines+=("network_monitor_up{layer=\"gateway\"} 1")
            prom_lines+=("network_monitor_latency_seconds{layer=\"gateway\"} $gw_latency")
            summary+=" gw:ok"
          else
            prom_lines+=("network_monitor_up{layer=\"gateway\"} 0")
            any_failure=1
            infra_failure=true
            summary+=" gw:FAIL"
          fi
        else
          prom_lines+=("network_monitor_up{layer=\"gateway\"} 0")
          any_failure=1
          infra_failure=true
          summary+=" gw:none"
        fi

        # Internet ping checks
        local internet_up=0
        local best_latency=""
        for target in "''${PING_TARGETS[@]}"; do
          local latency
          if latency=$(check_ping "$target"); then
            internet_up=1
            if [ -z "$best_latency" ]; then
              best_latency="$latency"
            fi
            summary+=" ping=$target:ok"
          else
            any_failure=1
            summary+=" ping=$target:FAIL"
          fi
        done
        prom_lines+=("network_monitor_up{layer=\"internet\"} $internet_up")
        [ -n "$best_latency" ] && prom_lines+=("network_monitor_latency_seconds{layer=\"internet\"} $best_latency")

        # DNS checks
        local dns_up=0
        local dns_latency=""
        for target in "''${DNS_TARGETS[@]}"; do
          local latency
          if latency=$(check_dns "$target"); then
            dns_up=1
            if [ -z "$dns_latency" ]; then
              dns_latency="$latency"
            fi
            summary+=" dns=$target:ok"
          else
            any_failure=1
            infra_failure=true
            summary+=" dns=$target:FAIL"
          fi
        done
        prom_lines+=("network_monitor_up{layer=\"dns\"} $dns_up")
        [ -n "$dns_latency" ] && prom_lines+=("network_monitor_latency_seconds{layer=\"dns\"} $dns_latency")

        # HTTP check
        local http_latency
        if http_latency=$(check_http); then
          prom_lines+=("network_monitor_up{layer=\"http\"} 1")
          prom_lines+=("network_monitor_latency_seconds{layer=\"http\"} $http_latency")
          summary+=" http:ok"
        else
          prom_lines+=("network_monitor_up{layer=\"http\"} 0")
          any_failure=1
          infra_failure=true
          summary+=" http:FAIL"
        fi

        # WiFi metrics
        local wifi_output
        wifi_output=$(collect_wifi)
        if [ -n "$wifi_output" ]; then
          while IFS= read -r line; do
            prom_lines+=("$line")
          done <<< "$wifi_output"
        fi

        # VPN metrics
        local vpn_output
        vpn_output=$(collect_vpn)
        if [ -n "$vpn_output" ]; then
          while IFS= read -r line; do
            prom_lines+=("$line")
          done <<< "$vpn_output"
        fi

        # Timestamp
        prom_lines+=("network_monitor_check_timestamp $(date +%s)")

        # Write prometheus metrics atomically
        printf '%s\n' "''${prom_lines[@]}" > "''${PROM_FILE}.tmp"
        mv "''${PROM_FILE}.tmp" "$PROM_FILE"

        # Log summary
        local ifaces
        ifaces=$(get_default_interfaces | tr '\n' ',')
        ifaces="''${ifaces%,}"
        echo "$(date -Iseconds)$summary ifaces=''${ifaces:-none}"

        # Dump diagnostics for real outages, not just ICMP being filtered
        if [ "$any_failure" -eq 1 ] && [ "$infra_failure" = true ]; then
          dump_diagnostics
        fi
      }

      echo "Network monitor started (interval: ''${INTERVAL}s)"
      while true; do
        run_checks || true
        sleep "$INTERVAL"
      done
    '';
  };
in {
  options.homelab.network-monitor = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable network connectivity monitoring";
    };

    wifi.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable WiFi-specific monitoring via iw station dump and node_exporter wifi collector";
    };

    port = {
      smokeping = lib.mkOption {
        type = lib.types.port;
        default = 9374;
        description = "Port for smokeping_prober";
      };

      unbound = lib.mkOption {
        type = lib.types.port;
        default = 9167;
        description = "Port for unbound_exporter";
      };
    };

    pingTargets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["1.1.1.1" "8.8.8.8"];
      description = "IP addresses to ping for internet connectivity checks";
    };

    dnsTargets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["google.com"];
      description = "Domains to resolve for DNS health checks";
    };

    httpTarget = lib.mkOption {
      type = lib.types.str;
      default = "http://detectportal.firefox.com/canonical.html";
      description = "URL for HTTP/TCP connectivity check";
    };

    interval = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = "Seconds between check cycles";
    };
  };

  config = lib.mkIf cfg.enable {
    # Local monitoring systemd service
    systemd.services.network-monitor = {
      description = "Network connectivity monitor";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = 10;
        ExecStart = lib.getExe monitorScript;
        # Network diagnostics need root for iw, wg, etc.
        DynamicUser = false;
      };
    };

    # Enable wifi collector on node_exporter when wifi monitoring is on
    services.prometheus.exporters.node.enabledCollectors =
      lib.mkIf cfg.wifi.enable ["wifi"];

    # smokeping_prober for latency histograms and packet loss
    services.prometheus.exporters.smokeping = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = cfg.port.smokeping;
      hosts = cfg.pingTargets;
    };

    # Enable unbound remote-control so the exporter can query stats
    services.unbound.settings.remote-control = {
      control-enable = true;
      control-interface = "/run/unbound/unbound.ctl";
    };

    # unbound_exporter for DNS resolver metrics
    services.prometheus.exporters.unbound = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = cfg.port.unbound;
      unbound.host = "unix:///run/unbound/unbound.ctl";
      # Unix socket does not need TLS certificates
      unbound.ca = null;
      unbound.certificate = null;
      unbound.key = null;
    };

    # Metrics proxy paths for prometheus scraping
    services.nginx.virtualHosts."metrics".locations = {
      "/metrics/smokeping".proxyPass = "http://127.0.0.1:${toString cfg.port.smokeping}/metrics";
      "/metrics/unbound".proxyPass = "http://127.0.0.1:${toString cfg.port.unbound}/metrics";
    };

    # Register scrape targets for prometheus discovery
    homelab.scrapeTargets = [
      {
        job = "network-smokeping";
        metricsPath = "/metrics/smokeping";
      }
      {
        job = "network-unbound";
        metricsPath = "/metrics/unbound";
      }
    ];

    # Alert rules for network issues
    homelab.alerts.network-monitor = [
      {
        alert = "NetworkMonitorDown";
        expr = ''network_monitor_up{layer="internet"} == 0'';
        for = "2m";
        labels = {
          severity = "critical";
          host = config.homelab.host.hostName;
          type = "host";
        };
        annotations.summary = "Internet connectivity lost for 2+ minutes";
      }
      {
        alert = "NetworkDNSDown";
        expr = ''network_monitor_up{layer="dns"} == 0'';
        for = "2m";
        labels = {
          severity = "critical";
          host = config.homelab.host.hostName;
          type = "host";
        };
        annotations.summary = "DNS resolution failing for 2+ minutes";
      }
      {
        alert = "WiFiSignalWeak";
        expr = ''network_monitor_wifi_signal_dbm < -75'';
        for = "5m";
        labels = {
          severity = "warning";
          host = config.homelab.host.hostName;
          type = "host";
        };
        annotations.summary = "WiFi signal below -75 dBm for 5+ minutes";
      }
      {
        alert = "VPNHandshakeStale";
        expr = ''network_monitor_vpn_handshake_age_seconds > 180'';
        for = "2m";
        labels = {
          severity = "warning";
          host = config.homelab.host.hostName;
          type = "host";
        };
        annotations.summary = "VPN handshake older than 3 minutes";
      }
      {
        alert = "DNSResolverUnhealthy";
        expr = ''rate(unbound_answers_total{rcode="SERVFAIL"}[5m]) > 0.1'';
        for = "5m";
        labels = {
          severity = "warning";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "Unbound SERVFAIL rate elevated";
      }
      {
        alert = "HighPacketLoss";
        expr = ''1 - rate(smokeping_response_duration_seconds_count[5m]) / rate(smokeping_requests_total[5m]) > 0.05'';
        for = "5m";
        labels = {
          severity = "warning";
          host = config.homelab.host.hostName;
          type = "host";
        };
        annotations.summary = "Packet loss exceeding 5% for 5+ minutes";
      }
    ];
  };
}
