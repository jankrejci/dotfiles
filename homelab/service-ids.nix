# Fixed user and group IDs for the services that move between the twins
#
# Files keep numeric owners when they are copied or sent with btrfs send.
# NixOS hands out IDs per host in the order users first appear, so the same
# service gets different numbers on thinkcenter and m75q. Pinning them makes a
# copied file mean the same owner on both. The numbers are thinkcenter's, so
# its files need no change. See docs/server-failover.md.
#
# Users whose ID NixOS already fixes, such as postgres or hass, and services
# with DynamicUser, such as prusa-obico, are not listed.
{
  config,
  lib,
  ...
}: let
  cfg = config.homelab;

  # A user only exists while its service is enabled, and defining a user
  # without its service would create a bare account, so every pin carries
  # the option that enables its service.
  pins = [
    {
      name = "alertmanager";
      uid = 975;
      gid = 971;
      enable = cfg.prometheus.enable;
    }
    {
      name = "oauth2-proxy";
      uid = 976;
      gid = 972;
      enable = cfg.sso-proxy.enable;
    }
    {
      name = "vaultwarden";
      uid = 978;
      gid = 974;
      enable = cfg.vaultwarden.enable;
    }
    {
      name = "netbird-mgmt";
      uid = 979;
      gid = 975;
      enable = cfg.netbird-server.enable;
    }
    {
      name = "dex";
      uid = 980;
      gid = 976;
      enable = cfg.dex.enable;
    }
    {
      name = "redis";
      uid = 981;
      gid = 977;
      enable = cfg.redis.enable;
    }
    {
      name = "memos";
      uid = 983;
      gid = 979;
      enable = cfg.memos.enable;
    }
    {
      name = "loki";
      uid = 986;
      gid = 983;
      enable = cfg.loki.enable;
    }
    {
      name = "jellyfin";
      uid = 987;
      gid = 984;
      enable = cfg.jellyfin.enable;
    }
    {
      name = "ntfy-sh";
      uid = 990;
      gid = 987;
      enable = cfg.ntfy.enable;
    }
    {
      name = "acme";
      uid = 991;
      gid = 989;
      enable = cfg.acme.wildcard;
    }
    {
      name = "immich";
      uid = 993;
      gid = 991;
      enable = cfg.immich.enable;
    }
  ];

  # grafana's user ID is fixed by NixOS, only its group is allocated per host.
  groupPins = [
    {
      name = "grafana";
      gid = 988;
      enable = cfg.grafana.enable;
    }
  ];

  active = lib.filter (p: p.enable) pins;
  activeGroups = lib.filter (p: p.enable) (pins ++ groupPins);
in {
  options.homelab.serviceIds.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    # Only the twins share files. Other hosts, like vpsfree with its own
    # alertmanager, keep the IDs they already have.
    description = "Pin the service user and group IDs shared by the twin servers";
  };

  config = lib.mkIf cfg.serviceIds.enable {
    users.users = lib.listToAttrs (map (p: lib.nameValuePair p.name {inherit (p) uid;}) active);
    users.groups = lib.listToAttrs (map (p: lib.nameValuePair p.name {inherit (p) gid;}) activeGroups);
  };
}
