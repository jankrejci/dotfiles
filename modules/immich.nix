{...}: let
  domain = "krejci.io";
  immichDomain = "immich.${domain}";
  immichPort = 2283;
  # Second disk for Immich data (NVMe)
  # Assumes partition is already created with label "disk-immich-luks"
  luksDevice = "/dev/disk/by-partlabel/disk-immich-luks";
in {
  # Allow nginx on VPN interface (proxies to Immich)
  networking.firewall.interfaces."nb-homelab".allowedTCPPorts = [80 443 immichPort];

  # NVMe data disk - TPM encrypted, not touched during deployment
  boot.initrd.luks.devices."immich-data" = {
    device = luksDevice;
    allowDiscards = true;
  };

  fileSystems."/var/lib/immich" = {
    device = "/dev/mapper/immich-data";
    fsType = "ext4";
    options = ["defaults" "nofail"];
  };

  services.immich = {
    enable = true;
    # Listen on all interfaces, security enforced via firewall
    host = "0.0.0.0";
    port = immichPort;
    # Media stored on dedicated NVMe disk at /var/lib/immich (default)
  };

  # Ensure required directory structure exists on the data disk
  systemd.tmpfiles.rules = [
    "d /var/lib/immich/upload 0755 immich immich -"
    "d /var/lib/immich/library 0755 immich immich -"
    "d /var/lib/immich/thumbs 0755 immich immich -"
    "d /var/lib/immich/profile 0755 immich immich -"
    "d /var/lib/immich/encoded-video 0755 immich immich -"
    "d /var/lib/immich/backups 0755 immich immich -"
    "f /var/lib/immich/upload/.immich 0644 immich immich -"
    "f /var/lib/immich/library/.immich 0644 immich immich -"
    "f /var/lib/immich/thumbs/.immich 0644 immich immich -"
    "f /var/lib/immich/profile/.immich 0644 immich immich -"
    "f /var/lib/immich/encoded-video/.immich 0644 immich immich -"
    "f /var/lib/immich/backups/.immich 0644 immich immich -"
  ];

  # Nginx reverse proxy - accessible via immich.x.nb
  services.nginx = {
    enable = true;
    virtualHosts.${immichDomain} = {
      listenAddresses = ["0.0.0.0"];
      locations."/" = {
        proxyPass = "http://localhost:${toString immichPort}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };
}
