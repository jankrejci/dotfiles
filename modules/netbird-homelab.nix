# System-level Netbird client for infrastructure access.
# Uses setup key enrollment for machine-based policies.
# Handles SSH, monitoring, and server-to-server communication.
{
  config,
  pkgs,
  ...
}: let
  setupKeyFile = "/var/lib/netbird-homelab/setup-key";
  daemonAddr = "unix:///var/run/netbird-homelab/sock";
in {
  # Netbird multi-instance client configuration
  services.netbird.clients = {
    homelab = {
      port = 51820;
      # Interface: nb-homelab
      # Setup key: /var/lib/netbird-homelab/setup-key
      # State: /var/lib/netbird-homelab/
    };
  };

  # Add capability to bind to port 53 for Netbird DNS
  systemd.services.netbird-homelab.serviceConfig.AmbientCapabilities = [
    "CAP_NET_ADMIN"
    "CAP_NET_RAW"
    "CAP_BPF"
    "CAP_NET_BIND_SERVICE"
  ];

  # Automatic enrollment using setup key on first boot.
  # The setup key is injected during deployment by nixos-install script.
  systemd.services.netbird-homelab-enroll = {
    description = "Enroll Netbird homelab client with setup key";
    wantedBy = ["multi-user.target"];
    after = ["netbird-homelab.service"];
    requires = ["netbird-homelab.service"];

    # Only run if setup key file exists, meaning we need to enroll
    unitConfig.ConditionPathExists = "${setupKeyFile}";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = 5;
      StartLimitBurst = 3;
      ExecStart = pkgs.writeShellScript "netbird-enroll" ''
        set -euo pipefail

        # Down existing connection to allow re-enrollment
        ${pkgs.netbird}/bin/netbird down --daemon-addr ${daemonAddr} 2>/dev/null || true

        # Enroll with setup key
        ${pkgs.netbird}/bin/netbird up \
          --daemon-addr ${daemonAddr} \
          --hostname ${config.networking.hostName} \
          --setup-key "$(cat ${setupKeyFile})"

        # Only reached after successful enrollment
        rm -f ${setupKeyFile}
      '';
    };
  };
}
