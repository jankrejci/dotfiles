# ESET Management Agent systemd service
#
# - runs ERA agent for centralized AV management
# - binary installed manually via eset-installer/
{
  config,
  lib,
  pkgs,
  ...
}: {
  systemd.services.eset = {
    description = "ESET Management Agent";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      Type = "simple";
      ExecStart = "/opt/eset/RemoteAdministrator/Agent/ERAAgent";
      Restart = "always";
      RestartSec = "10";
      User = "root";
      Group = "root";
      WorkingDirectory = "/opt/eset/RemoteAdministrator/Agent";

      # Service management
      KillMode = "mixed";
      TimeoutStopSec = "30";

      # Allow network access and file operations
      PrivateNetwork = false;
      NoNewPrivileges = false;
      PrivateDevices = false;
      PrivateTmp = false;
      ProtectSystem = false;
      ProtectHome = false;
    };

    # Ensure the patched binary exists
    preStart = ''
      if [ ! -x /opt/eset/RemoteAdministrator/Agent/ERAAgent ]; then
        echo "ERROR: ESET Agent binary not found or not executable"
        exit 1
      fi
    '';
  };
}
