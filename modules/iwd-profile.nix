# The iwd profile for one network, as the file iwd reads from
# /var/lib/iwd. Every writer of that file takes the format from here:
# modules/load-wifi.nix writes it into SD card images, modules/iso-wifi.nix
# into the installer, and `nix run .#wifi-push` sends it to a running host. A
# format spelled out in each of them drifts, and the drift is invisible until
# a profile iwd rejects reaches the card.
let
  # iwd only accepts an SSID verbatim as a filename when it is made up of
  # these characters; any other SSID needs an "=" prefix and the SSID
  # hex-encoded instead. That encoding is not implemented here, so such an
  # SSID is rejected with a clear error rather than written to a file iwd
  # ignores.
  isPlainSsid = ssid: builtins.match "[A-Za-z0-9_-]+" ssid != null;
in {
  stateDir = "/var/lib/iwd";
  pskSuffix = ".psk";

  # The caller supplies the passphrase. wifi-push has none at Nix build
  # time, so it renders this function applied to the printf conversion
  # `%s` and substitutes the value when the script runs. That keeps the
  # passphrase out of the format string, where a percent sign or a
  # backslash in it would otherwise read as printf syntax.
  profile = passphrase: ''
    [Security]
    Passphrase=${passphrase}

    [Settings]
    AutoConnect=true
  '';

  # The stored networks handed to an image build in WIFI_NETWORKS, the whole
  # decrypted secret as an object of SSID to passphrase. The build scripts set
  # it, so an image built without them simply carries no networks.
  networksFromEnv = let
    raw = builtins.getEnv "WIFI_NETWORKS";
    networks =
      if raw != ""
      then builtins.fromJSON raw
      else {};
    invalid = builtins.filter (ssid: !isPlainSsid ssid) (builtins.attrNames networks);
  in
    if invalid == []
    then networks
    else
      throw ''
        WIFI_NETWORKS has SSID(s) iwd cannot store as a plain filename: ${toString invalid}.
        iwd only accepts [A-Za-z0-9_-] verbatim; any other character needs
        "=" plus hex encoding, which is not implemented.
      '';
}
