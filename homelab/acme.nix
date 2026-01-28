# ACME wildcard certificates via Cloudflare DNS-01
#
# - wildcard cert for *.krejci.io
# - Cloudflare API token managed by agenix
# - cert readable by nginx group
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.acme;
in {
  options.homelab.acme = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable ACME wildcard certificates";
    };
  };

  config = lib.mkIf cfg.enable {
    # Cloudflare API token for DNS-01 challenge
    age.secrets.cloudflare-api-token = {
      rekeyFile = ../secrets/cloudflare-api-token.age;
      owner = "acme";
      group = "acme";
    };

    # Let's Encrypt ACME configuration for wildcard certificates
    # Uses DNS-01 challenge with Cloudflare API
    security.acme = {
      acceptTerms = true;
      defaults = {
        email = "admin@krejci.io";
        # Use DNS-01 challenge for wildcard certs (services are VPN-only)
        dnsProvider = "cloudflare";
        # Cloudflare API token managed by agenix-rekey
        # Format: CLOUDFLARE_DNS_API_TOKEN=token and CF_ZONE_API_TOKEN=token
        environmentFile = config.age.secrets.cloudflare-api-token.path;
        dnsResolver = "1.1.1.1:53"; # Use Cloudflare DNS for verification
      };
    };

    # Wildcard certificate for *.krejci.io
    security.acme.certs."krejci.io" = {
      domain = "*.krejci.io";
      extraDomainNames = ["krejci.io"];
      # Certificate will be readable by nginx group
      group = "nginx";
    };

    # Ensure ACME state directory exists with correct permissions
    systemd.tmpfiles.rules = [
      "d /var/lib/acme 0755 acme acme -"
    ];

    # Alert rules for ACME certificate renewal
    homelab.alerts.acme = [
      {
        alert = "AcmeFailed";
        expr = ''node_systemd_unit_state{name="acme-krejci.io.service",state="failed",host="${config.homelab.host.hostName}"} > 0'';
        labels = {
          severity = "critical";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "ACME certificate renewal failed";
      }
    ];

    # Health check
    homelab.healthChecks = [
      {
        name = "ACME";
        script = pkgs.writeShellApplication {
          name = "health-check-acme";
          runtimeInputs = [pkgs.systemd];
          text = ''
            result=$(systemctl show acme-krejci.io.service -p Result --value)
            if [ "$result" = "failed" ]; then
              echo "ACME renewal failed"
              exit 1
            fi
          '';
        };
        timeout = 10;
      }
    ];
  };
}
