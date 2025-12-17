{
  config,
  lib,
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
    # Let's Encrypt ACME configuration for wildcard certificates
    # Uses DNS-01 challenge with Cloudflare API
    security.acme = {
      acceptTerms = true;
      defaults = {
        email = "admin@krejci.io";
        # Use DNS-01 challenge for wildcard certs (services are VPN-only)
        dnsProvider = "cloudflare";
        # Cloudflare API token and zone ID stored in /var/lib/acme/cloudflare-api-token
        # Token is injected per-host during installation (not in git)
        # Format: CLOUDFLARE_DNS_API_TOKEN=token and CF_ZONE_API_TOKEN=zone_id
        environmentFile = "/var/lib/acme/cloudflare-api-token";
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
    systemd.tmpfiles.rules = [
      "d /var/lib/acme 0755 acme acme -"
    ];
  };
}
