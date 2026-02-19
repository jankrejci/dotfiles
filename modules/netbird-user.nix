# User-level Netbird client for desktop SSO authentication.
# Users authenticate via SSO through the tray UI, enabling user-based policies.
# Mutually exclusive with netbird-homelab (system client for servers).
#
# Profiles allow switching between Netbird instances without re-enrollment.
# The daemon stores profiles in $NB_STATE_DIR/{username}/{profile}.json and
# enriches the JSON after connecting. We seed minimal JSON via tmpfiles type
# "f" which only creates the file if missing.
#
# NOTE: Netbird 0.64.5 creates the per-user profile directory with 0600
# permissions, missing the execute bit. This causes all profile operations to
# fail because os.Stat returns EACCES and fileExists treats it as "exists".
# We work around this by pre-creating the directory with correct 0700 perms.
#
# WARNING: Netbird has a known routing table conflict issue when running
# multiple instances. The second instance may delete routes from the first.
# See: https://github.com/netbirdio/netbird/issues/2023
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.netbird-user;
  services = config.homelab.services;
  wrapperDir = config.security.wrapperDir;
  hostname = config.networking.hostName;
  netbirdDir = ".local/netbird-user";

  # CLI wrapper that uses the setcap binary and user daemon socket.
  # No --config flag needed: the daemon derives it from NB_STATE_DIR.
  netbirdUser = pkgs.writeShellScriptBin "netbird-user" ''
    exec ${wrapperDir}/netbird-user-daemon \
      --daemon-addr "unix://$XDG_RUNTIME_DIR/netbird-user/sock" \
      "$@"
  '';

  # UI wrapper connected to user daemon socket
  netbirdUserUI = pkgs.writeShellScriptBin "netbird-user-ui" ''
    exec ${pkgs.unstable.netbird-ui}/bin/netbird-ui \
      -daemon-addr "unix://$XDG_RUNTIME_DIR/netbird-user/sock" \
      "$@"
  '';
in {
  options.homelab.netbird-user = {
    profiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Named profiles for netbird-user. Keys are profile names, values are JSON config strings using Go url.URL struct format for ManagementURL.";
      example = {
        cloud = "{}";
        selfhosted = ''{"ManagementURL":{"Scheme":"https","Host":"api.example.com:443"}}'';
      };
    };
  };

  config = {
    # Seed profile JSON files into the per-user profile directory on first login.
    # Type "d" ensures directory exists with 0700 perms, working around the
    # netbird bug that creates it with 0600.
    # Type "f" only creates the file when missing, preserving daemon-enriched config.
    systemd.user.tmpfiles.rules =
      [
        "d %h/${netbirdDir} 0755 - - -"
        # Workaround: netbird 0.64.5 creates this directory with 0600, missing
        # the execute bit. Pre-create with 0700 so profile operations work.
        "d %h/${netbirdDir}/%u 0700 - - -"
        "d %t/netbird-user 0755 - - -"
      ]
      ++ lib.mapAttrsToList
      (name: json: "f %h/${netbirdDir}/%u/${name}.json 0600 - - - ${json}")
      cfg.profiles;

    # Grant capabilities to netbird binary for user service
    # Needs NET_ADMIN for interface creation, NET_RAW for raw sockets,
    # BPF for eBPF firewall, NET_BIND_SERVICE for DNS on port 53
    security.wrappers.netbird-user-daemon = {
      source = "${pkgs.unstable.netbird}/bin/netbird";
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
        NB_INTERFACE_NAME = services.netbird.interface;
        NB_WIREGUARD_PORT = toString services.netbird.port.nb;
        NB_LOG_LEVEL = "info";
        # Establish peer connections on demand instead of full mesh.
        # Requires server-side lazy_connection_enabled in dashboard too.
        NB_ENABLE_EXPERIMENTAL_LAZY_CONN = "true";
        # Store state and logs in user directory instead of /var/lib/netbird
        NB_STATE_DIR = "%h/${netbirdDir}";
        NB_LOG_FILE = "%h/${netbirdDir}/client.log";
      };

      serviceConfig = {
        Type = "simple";
        # No --config flag: the daemon derives config path from NB_STATE_DIR.
        # Profile system expects default profile at $NB_STATE_DIR/default.json.
        ExecStart = lib.concatStringsSep " " [
          "${wrapperDir}/netbird-user-daemon"
          "service run"
          "--daemon-addr unix://%t/netbird-user/sock"
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

    # Open firewall for WireGuard port
    networking.firewall.allowedUDPPorts = [services.netbird.port.nb];

    # Exclude user interface from NetworkManager and DHCP
    networking.networkmanager.unmanaged = lib.mkAfter [services.netbird.interface];
    networking.dhcpcd.denyInterfaces = [services.netbird.interface];

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
  };
}
