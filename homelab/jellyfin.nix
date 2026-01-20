# Jellyfin media server
#
# Server accessible at https://jellyfin.nb.krejci.io (VPN only)
# Media stored on secondary NVMe disk at /mnt/immich-data/jellyfin
#
# Setup:
# 1. After deployment, complete initial setup wizard at https://jellyfin.nb.krejci.io
# 2. Create Movies library with path: /var/lib/jellyfin/media/movies
# 3. Enable hardware transcoding: Dashboard → Playback → Intel Quick Sync Video (QSV)
# 4. Enable metrics: Dashboard → Advanced → Metrics → Enable Prometheus
#
# Upload media files:
#   scp movie.mp4 admin@thinkcenter.nb.krejci.io:/var/lib/jellyfin/media/movies/
#
# Files automatically get correct group ownership (jellyfin) via setgid bit.
# Scan library after upload: Dashboard → Libraries → Scan Library
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.jellyfin;
  global = config.homelab.global;
  services = config.homelab.services;
  hostName = config.homelab.host.hostName;
  domain = global.domain;
  jellyfinDomain = "${cfg.subdomain}.${domain}";

  # Secret paths
  secretsDir = "/var/lib/jellyfin/secrets";
  dexClientSecretPath = "${secretsDir}/dex-client";

  # Handler for writing dex client secret to jellyfin secrets directory
  dexSecretHandler = pkgs.writeShellApplication {
    name = "jellyfin-dex-handler";
    runtimeInputs = [pkgs.systemd];
    text = ''
      install -d -m 700 -o jellyfin -g jellyfin ${secretsDir}
      install -m 600 -o jellyfin -g jellyfin /dev/stdin ${dexClientSecretPath}
      systemctl restart jellyfin
    '';
  };

  # SSO configuration paths
  ssoConfigPath = "/var/lib/jellyfin/plugins/configurations/SSO-Auth.xml";
  brandingConfigPath = "/var/lib/jellyfin/config/branding.xml";

  # SSO config template with placeholders for runtime substitution
  ssoConfigTemplate = pkgs.substitute {
    src = ../assets/jellyfin/sso-config-template.xml;
    substitutions = ["--replace-fail" "@DEX_ENDPOINT@" "https://dex.${domain}"];
  };

  # Branding config hides native login, SSO button injected via nginx
  brandingConfig = ../assets/jellyfin/branding-template.xml;
in {
  options.homelab.jellyfin = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Jellyfin media server";
    };

    ip = lib.mkOption {
      type = lib.types.str;
      description = "IP address for nginx to listen on";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8096;
      description = "Port for Jellyfin server";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "jellyfin";
      description = "Subdomain for Jellyfin";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homelab.dex.enable;
        message = "homelab.jellyfin requires homelab.dex.enable = true for OAuth";
      }
    ];

    # Declare dex client secret for OAuth authentication
    homelab.secrets.jellyfin-dex = {
      generate = "token";
      handler = dexSecretHandler;
      username = "jellyfin-${hostName}";
      register = "dex";
    };

    # Register with Dex for OAuth authentication
    homelab.dex.clients = [
      {
        id = "jellyfin-${hostName}";
        name = "Jellyfin";
        redirectURIs = ["https://jellyfin.${domain}/sso/OID/redirect/Dex"];
      }
    ];

    # Register IP for services dummy interface
    homelab.serviceIPs = [cfg.ip];
    networking.hosts.${cfg.ip} = [jellyfinDomain];

    # Allow HTTPS on VPN interface
    networking.firewall.interfaces."${services.netbird.interface}".allowedTCPPorts = [services.https.port];

    # Bind mount jellyfin data from NVMe disk
    fileSystems."/var/lib/jellyfin" = {
      device = "/mnt/immich-data/jellyfin";
      fsType = "none";
      options = ["bind" "x-systemd.requires=mnt-immich\\x2ddata.mount"];
    };

    services.jellyfin = {
      enable = true;
      openFirewall = false;
    };

    # Add jellyfin user to render and video groups for hardware transcoding
    users.users.jellyfin.extraGroups = ["render" "video"];

    # Set published server URL for public sharing and configure SSO
    systemd.services.jellyfin = {
      environment.JELLYFIN_PublishedServerUrl = "https://${jellyfinDomain}";

      # Configure SSO plugin and branding before Jellyfin starts
      preStart = ''
        # Fail if SSO secret not provisioned
        [[ ! -f "${dexClientSecretPath}" ]] && {
          echo "ERROR: SSO secret not found at ${dexClientSecretPath}" >&2
          exit 1
        }

        # Write branding config with SSO login button
        cp "${brandingConfig}" "${brandingConfigPath}"

        # Substitute secret into SSO config template
        secret=$(cat "${dexClientSecretPath}")
        sed "s|@JELLYFIN_SSO_SECRET@|$secret|g" "${ssoConfigTemplate}" > "${ssoConfigPath}"

        echo "Jellyfin SSO configuration updated"
      '';
    };

    # Allow admin user to upload files directly
    users.users.admin.extraGroups = ["jellyfin"];

    # Ensure required directory structure exists
    systemd.tmpfiles.rules = [
      # Root data directory on NVMe disk
      "d /mnt/immich-data/jellyfin 0755 jellyfin jellyfin -"
      # Main state directory for bind mount target
      "d /var/lib/jellyfin 0750 jellyfin jellyfin -"
      # Media directories with setgid bit so uploaded files inherit jellyfin group
      "d /var/lib/jellyfin/media 2775 jellyfin jellyfin -"
      "d /var/lib/jellyfin/media/movies 2775 jellyfin jellyfin -"
      # Config directory for branding.xml
      "d /var/lib/jellyfin/config 0750 jellyfin jellyfin -"
      # Plugin config directory for SSO-Auth.xml
      "d /var/lib/jellyfin/plugins/configurations 0750 jellyfin jellyfin -"
    ];

    # Nginx reverse proxy
    #
    # SSO Button Injection:
    # Jellyfin 10.9+ uses DOMPurify to sanitize the branding LoginDisclaimer field,
    # which strips all HTML including forms and buttons. The official SSO plugin
    # does not provide a built-in login button UI.
    #
    # Workaround: nginx sub_filter injects JavaScript that creates the SSO button
    # dynamically. Uses setInterval to handle Jellyfin's SPA routing.
    #
    # If Jellyfin updates break this, check:
    # - Selector ".loginDisclaimer, #loginPage" may need updating
    # - https://github.com/9p4/jellyfin-plugin-sso for plugin compatibility
    services.nginx.virtualHosts.${jellyfinDomain} = {
      listenAddresses = [cfg.ip];
      forceSSL = true;
      useACMEHost = "${global.domain}";
      extraConfig = ''
        client_max_body_size 10G;
        sub_filter '</body>' '<script>
          (function() {
            const SSO_URL = "https://${jellyfinDomain}/sso/OID/start/Dex";
            function addSsoButton() {
              const container = document.querySelector(".loginDisclaimer, #loginPage");
              if (container && !document.getElementById("ssoBtn")) {
                const btn = document.createElement("a");
                btn.id = "ssoBtn";
                btn.href = SSO_URL;
                btn.className = "raised block emby-button";
                btn.style.cssText = "margin:1em auto;padding:1em 2em;display:block;text-align:center;max-width:25em;";
                btn.textContent = "Sign in with SSO";
                container.prepend(btn);
                clearInterval(intervalId);
              }
            }
            const intervalId = setInterval(addSsoButton, 500);
          })();
        </script></body>';
        sub_filter_once on;
        sub_filter_types text/html;
      '';
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
        # Disable compression so sub_filter can modify response
        extraConfig = "proxy_set_header Accept-Encoding '';";
      };
    };

    # Alert rules for jellyfin
    homelab.alerts.jellyfin = [
      {
        alert = "jellyfin-down";
        expr = ''node_systemd_unit_state{name="jellyfin.service",state="active",host="${hostName}"} == 0'';
        labels = {
          severity = "critical";
          host = hostName;
          type = "service";
        };
        annotations.summary = "Jellyfin service is not active";
      }
    ];

    homelab.healthChecks = [
      {
        name = "Jellyfin";
        script = pkgs.writeShellApplication {
          name = "health-check-jellyfin";
          runtimeInputs = [pkgs.systemd];
          text = ''
            systemctl is-active --quiet jellyfin.service
          '';
        };
        timeout = 10;
      }
    ];
  };
}
