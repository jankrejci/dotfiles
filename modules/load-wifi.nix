# Inject every stored WiFi network into SD card images during build.
#
# The networks come from WIFI_NETWORKS through modules/iwd-profile.nix, so this
# module never names a network itself.
#
# Each passphrase is interpolated into the image build script below, which
# lands it in the world-readable Nix store of the machine that builds the
# image, in both the .drv and the .img.
{lib, ...}: let
  iwdProfile = import ./iwd-profile.nix;
  networks = iwdProfile.networksFromEnv;
  ssids = builtins.attrNames networks;

  mkPskFile = ssid: let
    path = "./files${iwdProfile.stateDir}/${ssid}${iwdProfile.pskSuffix}";
  in ''
    printf '%s' ${lib.escapeShellArg (iwdProfile.profile networks.${ssid})} > ${lib.escapeShellArg path}
    chmod 600 ${lib.escapeShellArg path}
  '';
in {
  sdImage.populateRootCommands = lib.mkIf (ssids != []) (
    builtins.trace "Injecting WiFi profiles for: ${toString ssids}" ''
      mkdir -p ${lib.escapeShellArg "./files${iwdProfile.stateDir}"}
      ${lib.concatMapStringsSep "\n" mkPskFile ssids}
    ''
  );
}
