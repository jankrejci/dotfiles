# Ntfy notification service
#
# Simplified architecture: services declare their own secrets via homelab.secrets
# with register = "ntfy". The inject-secrets script calls ntfy.registerHandler
# to create the user and token in ntfy's database.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.ntfy;
  global = config.homelab.global;
  homelabServices = config.homelab.services;
  domain = global.domain;
  ntfyDomain = "${cfg.subdomain}.${domain}";

  # Handler for registering ntfy users and tokens.
  # Called by inject-secrets with username as $1 and token on stdin.
  registerHandler = pkgs.writeShellApplication {
    name = "ntfy-register";
    runtimeInputs = [pkgs.unstable.ntfy-sh pkgs.openssl];
    text = ''
      username="$1"
      token=$(cat)

      # Create user if not exists. ntfy user add fails if user exists.
      if ! ntfy user list 2>/dev/null | grep -q "^user $username"; then
        password=$(openssl rand -base64 32)
        printf '%s\n%s\n' "$password" "$password" | ntfy user add "$username"
      fi

      # Remove existing tokens and add the new one
      ntfy token remove "$username" --all 2>/dev/null || true
      ntfy token add --token "$token" "$username"
    '';
  };
in {
  options.homelab.ntfy = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Ntfy notification service";
    };

    ip = lib.mkOption {
      type = lib.types.str;
      description = "IP address for nginx to listen on";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 2586;
      description = "Port for ntfy server";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "ntfy";
      description = "Subdomain for ntfy";
    };

    # Expose registerHandler so inject-secrets can find it
    registerHandler = lib.mkOption {
      type = lib.types.package;
      default = registerHandler;
      description = "Handler script for registering ntfy users";
      internal = true;
    };
  };

  config = lib.mkIf cfg.enable {
    # Register IP for services dummy interface
    homelab.serviceIPs = [cfg.ip];
    networking.hosts.${cfg.ip} = [ntfyDomain];

    # Allow HTTPS on VPN interface only
    networking.firewall.interfaces."${homelabServices.netbird.interface}".allowedTCPPorts = [
      homelabServices.https.port
    ];

    # Use unstable ntfy-sh for template support (requires >= 2.14.0)
    services.ntfy-sh = {
      enable = true;
      package = pkgs.unstable.ntfy-sh;
      settings = {
        # Listen on 127.0.0.1 only, accessed via nginx proxy
        listen-http = "127.0.0.1:${toString cfg.port}";
        base-url = "https://${ntfyDomain}";
        # Authentication: read-only by default, publishing requires tokens
        auth-default-access = "read-only";
        auth-file = "/var/lib/ntfy-sh/user.db";
        # Template directory for custom webhook formatting
        template-dir = "/var/lib/ntfy-sh/templates";
        # Expose Prometheus metrics on 127.0.0.1 only
        metrics-listen-http = "127.0.0.1:9091";
      };
    };

    # Install webhook templates for Prometheus alerts
    systemd.tmpfiles.rules = [
      "d /var/lib/ntfy-sh/templates 0755 ntfy-sh ntfy-sh -"
      "L+ /var/lib/ntfy-sh/templates/prometheus-host.yml - - - - ${../assets/ntfy/prometheus-host.yml}"
      "L+ /var/lib/ntfy-sh/templates/prometheus-service.yml - - - - ${../assets/ntfy/prometheus-service.yml}"
      "L+ /var/lib/ntfy-sh/templates/default.yml - - - - ${../assets/ntfy/default.yml}"
    ];

    services.nginx.virtualHosts.${ntfyDomain} = {
      listenAddresses = [cfg.ip];
      forceSSL = true;
      useACMEHost = domain;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };

    # Ntfy metrics via unified metrics proxy
    services.nginx.virtualHosts."metrics".locations."/metrics/ntfy".proxyPass = "http://127.0.0.1:9091/metrics";

    # Health check
    homelab.healthChecks = [
      {
        name = "Ntfy";
        script = pkgs.writeShellApplication {
          name = "health-check-ntfy";
          runtimeInputs = [pkgs.systemd];
          text = ''
            systemctl is-active --quiet ntfy-sh.service
          '';
        };
        timeout = 10;
      }
    ];
  };
}
