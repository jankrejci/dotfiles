{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.acme;
  hostName = config.homelab.host.hostName;

  # Secret path
  cloudflareTokenPath = "/var/lib/acme/secrets/cloudflare-token";

  # Handler for writing Cloudflare API token to ACME secrets directory
  cloudflareHandler = pkgs.writeShellApplication {
    name = "acme-cloudflare-handler";
    text = ''
      install -d -m 700 -o acme -g acme /var/lib/acme/secrets
      install -m 600 -o acme -g acme /dev/stdin ${cloudflareTokenPath}
    '';
  };
in {
  options.homelab.acme = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable ACME wildcard certificates";
    };
  };

  config = lib.mkIf cfg.enable {
    # Secret declaration for inject-secrets script.
    # User must provide actual Cloudflare API token when prompted.
    homelab.secrets.cloudflare-token = {
      generate = "ask";
      handler = cloudflareHandler;
    };

    # Let's Encrypt ACME configuration for wildcard certificates
    # Uses DNS-01 challenge with Cloudflare API
    security.acme = {
      acceptTerms = true;
      defaults = {
        email = "admin@krejci.io";
        # Use DNS-01 challenge for wildcard certs (services are VPN-only)
        dnsProvider = "cloudflare";
        # Cloudflare API token and zone ID stored in secrets/
        # Token is injected per-host during installation (not in git)
        # Format: CLOUDFLARE_DNS_API_TOKEN=token and CF_ZONE_API_TOKEN=zone_id
        environmentFile = cloudflareTokenPath;
        # Alternatively, use credentialFiles for newer NixOS
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
    # Note: secrets/ subdirectory is auto-created by homelab.secrets
    systemd.tmpfiles.rules = [
      "d /var/lib/acme 0755 acme acme -"
    ];

    # Alert rules for ACME certificate renewal
    homelab.alerts.acme = [
      {
        alert = "acme-failed";
        expr = ''node_systemd_unit_state{name="acme-krejci.io.service",state="failed",host="${hostName}"} > 0'';
        labels = {
          severity = "critical";
          host = hostName;
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
