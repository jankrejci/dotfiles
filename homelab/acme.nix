# ACME certificates via Cloudflare DNS-01
#
# - wildcard cert for the configured domain
# - optional cert for the host's own Netbird peer name
# - Cloudflare API token managed by agenix
# - certs readable by nginx group
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.acme;
  global = config.homelab.global;
  domain = global.domain;
  hostDomain = "${config.homelab.host.hostName}.${global.peerDomain}";

  # The wildcard covers only one label below the domain, so a peer name like
  # prusa.nb.krejci.io needs a certificate of its own.
  certNames = lib.optional cfg.wildcard domain ++ lib.optional cfg.hostCert hostDomain;
  acmeServices = map (name: "acme-${name}.service") certNames;
in {
  options.homelab.acme = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable ACME certificates";
    };

    email = lib.mkOption {
      type = lib.types.str;
      default = "admin@${domain}";
      description = "Email address for Let's Encrypt account registration";
    };

    wildcard = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Issue the wildcard certificate for the configured domain";
    };

    hostCert = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Issue a certificate for the host's Netbird peer name";
    };

    hostDomain = lib.mkOption {
      type = lib.types.str;
      default = hostDomain;
      readOnly = true;
      description = "Netbird peer name the host certificate is issued for";
    };
  };

  config = lib.mkIf cfg.enable {
    # Cloudflare API token for DNS-01 challenge
    age.secrets.cloudflare-api-token = {
      rekeyFile = ../secrets/cloudflare-api-token.age;
      owner = "acme";
      group = "acme";
    };

    # Let's Encrypt ACME configuration
    # Uses DNS-01 challenge with Cloudflare API
    security.acme = {
      acceptTerms = true;
      defaults = {
        email = cfg.email;
        # Use DNS-01 challenge since services are VPN-only
        dnsProvider = "cloudflare";
        # Cloudflare API token managed by agenix-rekey
        # Format: CLOUDFLARE_DNS_API_TOKEN=token and CF_ZONE_API_TOKEN=token
        environmentFile = config.age.secrets.cloudflare-api-token.path;
        dnsResolver = "1.1.1.1:53"; # Use Cloudflare DNS for verification
      };

      # Certificates will be readable by nginx group
      certs =
        lib.optionalAttrs cfg.wildcard {
          ${domain} = {
            domain = "*.${domain}";
            extraDomainNames = [domain];
            group = "nginx";
          };
        }
        // lib.optionalAttrs cfg.hostCert {
          ${hostDomain}.group = "nginx";
        };
    };

    # Ensure ACME state directory exists with correct permissions
    systemd.tmpfiles.rules = [
      "d /var/lib/acme 0755 acme acme -"
    ];

    # Alert rules for ACME certificate renewal
    homelab.alerts.acme =
      map (service: {
        alert = "AcmeFailed";
        expr = ''node_systemd_unit_state{name="${service}",state="failed",host="${config.homelab.host.hostName}"} > 0'';
        labels = {
          severity = "critical";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "ACME certificate renewal failed";
      })
      acmeServices;

    # Health check
    homelab.healthChecks = [
      {
        name = "ACME";
        script = pkgs.writeShellApplication {
          name = "health-check-acme";
          runtimeInputs = [pkgs.systemd];
          text = ''
            for service in ${lib.escapeShellArgs acmeServices}; do
              result=$(systemctl show "$service" -p Result --value)
              if [ "$result" = "failed" ]; then
                echo "ACME renewal failed for $service"
                exit 1
              fi
            done
          '';
        };
        timeout = 10;
      }
    ];
  };
}
