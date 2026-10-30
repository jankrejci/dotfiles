# Join every stored WiFi network from the installer ISO without any input.
#
# The ISO root is read-only and /var/lib lives in RAM, so the profiles ship in
# /etc and a boot service copies them to where iwd reads them, the same way
# modules/load-keys.nix places the Netbird setup key.
#
# NetworkManager comes from the NixOS installer profile only for configuring
# networks by hand. Here systemd-networkd already runs DHCP on wired and wifi
# links and iwd joins the stored networks, so NetworkManager would only compete
# with networkd for the same interfaces. A network that is not stored is
# joined with `iwctl station wlan0 connect <ssid>`.
#
# Each passphrase lands in the world-readable Nix store of the machine that
# builds the ISO.
{lib, ...}: let
  iwdProfile = import ./iwd-profile.nix;
  networks = iwdProfile.networksFromEnv;
  ssids = builtins.attrNames networks;
  profileDir = "iwd-profiles";
in {
  networking.networkmanager.enable = lib.mkForce false;

  environment.etc = lib.mapAttrs' (ssid: passphrase:
    lib.nameValuePair "${profileDir}/${ssid}${iwdProfile.pskSuffix}" {
      text = iwdProfile.profile passphrase;
      mode = "0600";
    })
  (builtins.trace "Injecting WiFi profiles for: ${toString ssids}" networks);

  systemd.services.iwd-profiles-copy = lib.mkIf (ssids != []) {
    description = "Copy stored WiFi profiles for iwd";
    wantedBy = ["multi-user.target"];
    before = ["iwd.service"];
    after = ["local-fs.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      install -d -m 700 ${iwdProfile.stateDir}
      install -m 600 /etc/${profileDir}/*${iwdProfile.pskSuffix} ${iwdProfile.stateDir}/
    '';
  };
}
