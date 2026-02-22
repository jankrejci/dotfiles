# System-level Netbird client for infrastructure access.
# Uses setup key enrollment for machine-based policies.
# Handles SSH, monitoring, and server-to-server communication.
{
  config,
  lib,
  pkgs,
  ...
}: let
  services = config.homelab.services;
  global = config.homelab.global;
  clientName = "homelab";
  setupKeyFile = "/var/lib/netbird-${clientName}/setup-key";
  daemonAddr = "unix:///var/run/netbird-${clientName}/sock";
  managementUrl = "https://api.${global.domain}";
in {
  config = {
    services.netbird.package = pkgs.unstable.netbird;
    services.netbird.clients.${clientName} = {
      port = services.netbird.port.wireguard;
      interface = services.netbird.interface;
    };

    # Add capability to bind to port 53 for Netbird DNS
    systemd.services.netbird-homelab.serviceConfig.AmbientCapabilities = [
      "CAP_NET_ADMIN"
      "CAP_NET_RAW"
      "CAP_BPF"
      "CAP_NET_BIND_SERVICE"
    ];

    # Allow netbird service to configure DNS via systemd-resolved.
    # Required for peer name resolution via nb.krejci.io domain.
    # See also: netbird-user.nix has a similar rule for desktop users.
    security.polkit.enable = true;
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        var start = "org.freedesktop.resolve1.";
        var allowed = [
          "set-dns-servers",
          "set-domains",
          "set-default-route",
          "set-dnssec",
          "set-dns-over-tls",
          "revert"
        ];
        if (action.id.indexOf(start) === 0 &&
            allowed.indexOf(action.id.slice(start.length)) !== -1 &&
            subject.user === "netbird-homelab") {
          return polkit.Result.YES;
        }
      });
    '';

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
          ${pkgs.unstable.netbird}/bin/netbird down --daemon-addr ${daemonAddr} 2>/dev/null || true

          # Enroll with setup key
          ${pkgs.unstable.netbird}/bin/netbird up \
            --daemon-addr ${daemonAddr} \
            --hostname ${config.networking.hostName} \
            --management-url ${managementUrl} \
            --setup-key "$(cat ${setupKeyFile})"

          # Only reached after successful enrollment
          rm -f ${setupKeyFile}
        '';
      };
    };
  };
}
