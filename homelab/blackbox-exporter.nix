# TLS certificate monitoring via blackbox exporter
#
# Probes TLS endpoints and exposes certificate expiry metrics.
# Prometheus scrapes the blackbox exporter with multi-target pattern
# to check nginx vhosts on this host that use ACME certificates.
#
# Targets are service IPs rather than domain names. Both resolve to the
# same address, but IPs avoid a DNS dependency. Since the wildcard cert
# has no IP SANs, the probe uses insecure_skip_verify to complete the
# handshake. This is fine because we only read the expiry date, not
# validate trust chains.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.blackbox-exporter;
  services = config.homelab.services;
in {
  options.homelab.blackbox-exporter = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable blackbox exporter for TLS certificate monitoring";
    };

    port = lib.mkOption {
      type = lib.types.port;
      description = "Port for blackbox exporter";
    };

    targets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "TLS endpoints to probe, as host:port strings";
    };
  };

  config = lib.mkIf cfg.enable {
    # Blackbox exporter with TLS probe module
    services.prometheus.exporters.blackbox = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = cfg.port;
      configFile = pkgs.writeText "blackbox.yml" (builtins.toJSON {
        modules = {
          tls_connect = {
            prober = "tcp";
            tcp = {
              tls = true;
              # Probes connect by service IP but certs are for *.domain.
              # We only need the expiry metric, not hostname verification.
              tls_config.insecure_skip_verify = true;
            };
          };
        };
      });
    };

    # Auto-discover TLS endpoints from nginx vhosts with ACME certs.
    # Only include vhosts that bind to explicit service IPs. Vhosts without
    # listenAddresses use the SSO proxy pattern and share another vhost's IP.
    # Every listenAddress is probed, since a vhost may bind both its service
    # IP and the WG-tunnel IP for the public-facing path.
    homelab.blackbox-exporter.targets = let
      vhosts = config.services.nginx.virtualHosts;
      tlsVhosts = lib.filterAttrs (_: vh:
        vh.useACMEHost != null && vh.listenAddresses != [])
      vhosts;
      mkTargets = _name: vh: map (addr: "${addr}:${toString services.https.port}") vh.listenAddresses;
    in
      # Several vhosts may bind the same WG-tunnel IP, deduplicate so the
      # generated config lists each endpoint once.
      lib.unique (lib.flatten (lib.mapAttrsToList mkTargets tlsVhosts));

    # Metrics endpoint via unified metrics proxy
    services.nginx.virtualHosts."metrics".locations."/metrics/blackbox".proxyPass = "http://127.0.0.1:${toString cfg.port}/metrics";

    # Register scrape target for the exporter itself
    homelab.scrapeTargets = [
      {
        job = "blackbox";
        metricsPath = "/metrics/blackbox";
      }
    ];

    # Alert rules for certificate expiry and probe failures
    homelab.alerts.blackbox = [
      {
        alert = "TlsCertExpiringSoon";
        expr = ''(probe_ssl_earliest_cert_expiry - time()) / 86400 < 14'';
        for = "1h";
        labels = {
          severity = "warning";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "TLS certificate expires in less than 14 days";
      }
      {
        alert = "TlsCertExpired";
        expr = ''probe_ssl_earliest_cert_expiry - time() < 0'';
        labels = {
          severity = "critical";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "TLS certificate has expired";
      }
      {
        alert = "TlsProbeDown";
        expr = ''probe_success{job="blackbox-tls"} == 0'';
        for = "5m";
        labels = {
          severity = "critical";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "TLS probe failing";
      }
    ];

    # Health check
    homelab.healthChecks = [
      {
        name = "Blackbox Exporter";
        script = pkgs.writeShellApplication {
          name = "health-check-blackbox";
          runtimeInputs = [pkgs.systemd];
          text = ''
            systemctl is-active --quiet prometheus-blackbox-exporter.service
          '';
        };
        timeout = 10;
      }
    ];
  };
}
