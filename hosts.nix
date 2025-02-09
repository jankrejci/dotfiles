{ nixpkgs, ... }:
{
  vpsfree = {
    ipAddress = "192.168.99.1";
    wgPublicKey = "iWfrqdXV4bDQOCfhlZ2KRS7eq2B/QI440HylPrzJUww=";
    system = "x86_64-linux";
    extraModules = [
      ./modules/users/admin/user.nix
      ./modules/wg-server.nix
      ./modules/grafana.nix
      ./modules/vpsadminos.nix
    ];
  };
  rpi4 = {
    ipAddress = "192.168.99.2";
    wgPublicKey = "sUUZ9eIfyjqdEDij7vGnOe3sFbbF/eHQqS0RMyWZU0c=";
    system = "aarch64-linux";
    extraModules = [
      "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
      ./modules/users/admin/user.nix
      ./modules/wg-client.nix
    ];
  };
  optiplex = {
    ipAddress = "192.168.99.3";
    wgPublicKey = "6QNJxFoSDKwqQjF6VgUEWP5yXXe4J3DORGo7ksQscFA=";
    system = "x86_64-linux";
    extraModules = [
      ./modules/users/jkr/user.nix
      ./modules/users/paja/user.nix
      ./modules/wg-client.nix
      ./modules/desktop.nix
    ];
  };
  thinkpad = {
    ipAddress = "192.168.99.4";
    wgPublicKey = "IzW6yPZJdrBC6PtfSaw7k4hjH+b/GjwvwiDLkLevLDI=";
    system = "x86_64-linux";
    extraModules = [
      ./modules/users/jkr/user.nix
      ./modules/users/paja/user.nix
      ./modules/wg-client.nix
      ./modules/desktop.nix
      ./modules/disable-nvidia.nix
    ];
  };
  latitude = {
    ipAddress = "192.168.99.5";
    wgPublicKey = "ggj+uqF/vij5V+fA5r9GIv5YuT9hX7OBp+lAGYh5SyQ=";
  };
  android = {
    ipAddress = "192.168.99.6";
    wgPublicKey = "HP+nPkrKwAxvmXjrI9yjsaGRMVXqt7zdcBGbD2ji83g=";
  };
}
