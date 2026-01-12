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
  jellyfinDomain = "${cfg.subdomain}.${global.domain}";
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

    # Set published server URL for public sharing
    systemd.services.jellyfin.environment = {
      JELLYFIN_PublishedServerUrl = "https://${jellyfinDomain}";
    };

    # Allow admin user to upload files directly
    users.users.admin.extraGroups = ["jellyfin"];

    # Ensure required directory structure exists on the data disk
    # setgid bit (2775) ensures new files inherit jellyfin group
    systemd.tmpfiles.rules = [
      "d /mnt/immich-data/jellyfin 0755 jellyfin jellyfin -"
      "d /var/lib/jellyfin 0750 jellyfin jellyfin -"
      "d /var/lib/jellyfin/media 2775 jellyfin jellyfin -"
      "d /var/lib/jellyfin/media/movies 2775 jellyfin jellyfin -"
    ];

    # Nginx reverse proxy
    services.nginx.virtualHosts.${jellyfinDomain} = {
      listenAddresses = [cfg.ip];
      forceSSL = true;
      useACMEHost = "${global.domain}";
      # Allow large media file uploads
      extraConfig = "client_max_body_size 10G;";
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };

    # Alert rules for jellyfin
    homelab.alerts.jellyfin = [
      {
        alert = "JellyfinDown";
        expr = ''node_systemd_unit_state{name="jellyfin.service",state="active",host="${config.homelab.host.hostName}"} == 0'';
        labels = {
          severity = "critical";
          host = config.homelab.host.hostName;
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
