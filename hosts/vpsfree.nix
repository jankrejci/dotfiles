# vpsAdminOS VPS container configuration
#
# - NFS mount from NAS for borg backups
# - container-specific systemd workarounds
# - fixed DNS since no DHCP in container
{
  config,
  lib,
  pkgs,
  ...
}: let
  nasHost = "172.16.130.249";
  nasPath = "/nas/6057";
  mountPoint = "/mnt/nas-backup";
in {
  # vpsAdminOS containers don't support tmpfs on /tmp with systemd mount namespacing
  boot.tmp.useTmpfs = lib.mkForce false;

  systemd.settings.Manager.DefaultTimeoutStartSec = "900s";

  # Avoid collision between networking and vpsadminos module
  systemd.network.networks."98-all-ethernet".DHCP = "no";

  # Disable wait-online - network is managed by vpsAdminOS host, not systemd-networkd
  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;

  # Disable systemd-hostnamed - fails in container trying to access /sys/firmware/acpi
  systemd.services.systemd-hostnamed.enable = lib.mkForce false;

  # Deploys arrive over the VPN, but this host also serves the netbird control
  # plane to itself: management and signal via local nginx, DNS via local
  # unbound, thinkcenter via the local WG tunnel. Restarting netbird together
  # with those dependencies leaves the client in exponential backoff for over
  # two minutes, deploy-rs never gets its confirmation and magic rollback
  # reverts a healthy activation. Keep netbird running across activations and
  # restart it manually after a deploy that changed its package:
  #   systemd-run --on-active=5s systemctl restart netbird-homelab
  systemd.services.netbird-homelab.restartIfChanged = false;

  # There is no DHCP, so fixed dns is needed
  networking.nameservers = ["1.1.1.1" "8.8.8.8"];

  # NFS client requires rpcbind for mount.nfs helper to resolve NFS server ports.
  boot.supportedFilesystems = ["nfs"];
  services.rpcbind.enable = true;

  # NFS mount from NAS. Automount is unsupported in vpsAdminOS containers,
  # so we use a regular mount that starts after network is online.
  systemd.mounts = [
    {
      what = "${nasHost}:${nasPath}";
      where = mountPoint;
      type = "nfs";
      options = "soft,timeo=30,retrans=3,nofail";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target" "rpcbind.service"];
      wants = ["network-online.target"];
      requires = ["rpcbind.service"];
    }
  ];

  # Symlink borg repos to NAS mount point.
  # Immutable flag on mount point prevents accidental writes when NFS is unmounted.
  systemd.tmpfiles.rules = [
    "d ${mountPoint} 0755 root root -"
    "h ${mountPoint} - - - - +i"
    "L /var/lib/borg-repos - - - - ${mountPoint}/borg-repos"
  ];

  # Borg user needs bash shell because borg client executes `borg serve` via SSH.
  # Security is via filesystem permissions, not SSH command restrictions.
  users.users.borg = {
    isSystemUser = true;
    group = "borg";
    shell = "${pkgs.bash}/bin/bash";
    home = "/var/lib/borg";
    createHome = true;
  };

  users.groups.borg = {};

  environment.systemPackages = with pkgs; [
    borgbackup
    nfs-utils # mount.nfs helper for systemd mount unit
  ];

  homelab.alerts.hosts = [
    {
      alert = "VpsfreeDown";
      expr = ''up{instance=~"vpsfree.*", job="node"} == 0'';
      labels = {
        severity = "critical";
        host = config.homelab.host.hostName;
        type = "host";
      };
      annotations.summary = "vpsfree host is down";
    }
  ];
}
