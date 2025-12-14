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
{config, ...}: let
  services = config.serviceConfig;
  host = config.hostConfig.self;
  jellyfinDomain = "${services.jellyfin.subdomain}.${services.global.domain}";
in {
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

  # Wait for services interface before binding
  systemd.services.nginx.after = ["sys-subsystem-net-devices-services.device"];

  # Nginx reverse proxy
  services.nginx = {
    enable = true;
    virtualHosts.${jellyfinDomain} = {
      listenAddresses = [host.services.jellyfin.ip];
      # Enable HTTPS with Let's Encrypt wildcard certificate
      forceSSL = true;
      useACMEHost = "${services.global.domain}";
      # Allow large media file uploads
      extraConfig = "client_max_body_size 10G;";
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString services.jellyfin.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };
}
