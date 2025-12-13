# User-level Netbird client for desktop SSO authentication.
# Runs alongside the system-level netbird-homelab client.
# Users authenticate via SSO through the tray UI, enabling user-based policies.
#
# WARNING: Netbird has a known routing table conflict issue when running
# multiple instances. The second instance may delete routes from the first.
# See: https://github.com/netbirdio/netbird/issues/2023
# This module is experimental until upstream fixes the conflict.
{
  config,
  lib,
  pkgs,
  ...
}: let
  wrapperDir = config.security.wrapperDir;
  hostname = config.networking.hostName;
  netbirdDir = ".local/netbird-user";

  # CLI wrapper that uses the setcap binary and custom paths
  netbirdUser = pkgs.writeShellScriptBin "netbird-user" ''
    exec ${wrapperDir}/netbird-user-daemon \
      --config "$HOME/${netbirdDir}/config.json" \
      --daemon-addr "unix://$XDG_RUNTIME_DIR/netbird-user/sock" \
      "$@"
  '';

  # UI wrapper connected to user daemon socket
  netbirdUserUI = pkgs.writeShellScriptBin "netbird-user-ui" ''
    exec ${pkgs.netbird-ui}/bin/netbird-ui \
      -daemon-addr "unix://$XDG_RUNTIME_DIR/netbird-user/sock" \
      "$@"
  '';
in {
  # Grant capabilities to netbird binary for user service
  # Needs NET_ADMIN for interface creation, NET_RAW for raw sockets,
  # BPF for eBPF firewall, NET_BIND_SERVICE for DNS on port 53
  security.wrappers.netbird-user-daemon = {
    source = "${pkgs.netbird}/bin/netbird";
    owner = "root";
    group = "root";
    capabilities = "cap_net_admin,cap_net_raw,cap_net_bind_service,cap_bpf+ep";
  };

  # Systemd user service for the netbird daemon
  systemd.user.services.netbird-user = {
    description = "Netbird user-level VPN client";
    after = ["network.target"];
    wantedBy = ["graphical-session.target"];

    environment = {
      # Use different interface and port than system client
      NB_INTERFACE_NAME = "nb-user";
      NB_WIREGUARD_PORT = "51821";
      NB_LOG_LEVEL = "info";
      # Store state and logs in user directory instead of /var/lib/netbird
      NB_STATE_DIR = "%h/${netbirdDir}";
      NB_LOG_FILE = "%h/${netbirdDir}/client.log";
    };

    serviceConfig = {
      Type = "simple";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %t/netbird-user %h/${netbirdDir}";
      ExecStart = "${wrapperDir}/netbird-user-daemon service run --config %h/${netbirdDir}/config.json --daemon-addr unix://%t/netbird-user/sock";
      # Workaround: netbird ignores NB_INTERFACE_NAME and NB_WIREGUARD_PORT env vars
      # after config.json exists. The daemon creates config with wrong defaults on
      # first start. Running "up" with flags fixes the config. Timeout prevents
      # blocking on SSO prompt; "-" ignores the non-zero exit from timeout.
      ExecStartPost = lib.concatStringsSep " " [
        "-${pkgs.coreutils}/bin/timeout"
        "5"
        "${netbirdUser}/bin/netbird-user"
        "up"
        "--interface-name nb-user"
        "--wireguard-port 51821"
        "--hostname ${hostname}"
      ];
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  environment.systemPackages = [
    netbirdUser
    netbirdUserUI
  ];

  # Autostart tray UI when graphical session starts
  environment.etc."xdg/autostart/netbird-user-ui.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Netbird User VPN
    Comment=User-level Netbird VPN with SSO authentication
    Exec=${netbirdUserUI}/bin/netbird-user-ui
    Icon=netbird
    Terminal=false
    Categories=Network;
    X-GNOME-Autostart-enabled=true
  '';

  # Open firewall for user WireGuard port
  networking.firewall.allowedUDPPorts = [51821];

  # Exclude user interface from NetworkManager and DHCP
  networking.networkmanager.unmanaged = lib.mkAfter ["nb-user"];
  networking.dhcpcd.denyInterfaces = ["nb-user"];

  # Allow users to configure DNS via systemd-resolved for VPN.
  # Netbird needs to set DNS servers and routing domains for peer resolution.
  # Same pattern used by OpenVPN's update-systemd-resolved script.
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
          subject.isInGroup("users")) {
        return polkit.Result.YES;
      }
    });
  '';
}
