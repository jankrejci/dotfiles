{ lib, nixpkgs, ... }:

with lib;

{
  options.hosts = mkOption {
    description = "A set of defined hosts";
    # Explicitly pass `name`
    type = types.attrsOf (types.submodule ({ config, name, ... }: {
      options = {
        hostName = mkOption {
          type = types.str;
          # Use the attribute name (e.g., "vpsfree") as default
          default = name;
          description = "The hostname of the system.";
        };

        ipAddress = mkOption {
          type = types.str;
          description = "IP address of the host";
        };

        wgPublicKey = mkOption {
          type = types.str;
          description = "WireGuard public key";
        };

        system = mkOption {
          type = types.str;
          default = "x86_64-linux";
          description = "System architecture";
        };

        kind = mkOption {
          type = types.str;
          default = "nixos";
          description = "System architecture";
        };

        extraModules = mkOption {
          type = types.listOf types.path;
          default = [ ];
          description = "Extra NixOS modules to include";
        };
      };
    }));
  };


  ### Servers ###
  config.hosts = {
    vpsfree = {
      ipAddress = "192.168.99.1";
      wgPublicKey = "iWfrqdXV4bDQOCfhlZ2KRS7eq2B/QI440HylPrzJUww=";
      extraModules = [
        ./modules/grafana.nix
        ./modules/vpsadminos.nix
        ./modules/wg-server.nix
      ];
    };

    thinkcenter = {
      ipAddress = "192.168.99.2";
      wgPublicKey = "1oh3e+TaDcOFlxBTm6A3WYBkvQSNDPlnzK7FQc1DxVM=";
      extraModules = [
        ./modules/disk.nix
      ];
    };

    ### Desktops ###

    thinkpad = {
      ipAddress = "192.168.99.21";
      wgPublicKey = "IzW6yPZJdrBC6PtfSaw7k4hjH+b/GjwvwiDLkLevLDI=";
      extraModules = [
        ./modules/users/jkr/user.nix
        ./modules/users/paja/user.nix
        ./modules/desktop.nix
        ./modules/disable-nvidia.nix
      ];
    };

    optiplex = {
      ipAddress = "192.168.99.22";
      wgPublicKey = "6QNJxFoSDKwqQjF6VgUEWP5yXXe4J3DORGo7ksQscFA=";
      extraModules = [
        ./modules/users/jkr/user.nix
        ./modules/users/paja/user.nix
        ./modules/desktop.nix
      ];
    };

    framework = {
      ipAddress = "192.168.99.23";
      wgPublicKey = "9YMpp9mFeXXbe04SmEpwBMcUrBf7XEf/sdregqrkBDw=";
      extraModules = [
        ./modules/users/jkr/user.nix
        ./modules/users/paja/user.nix
        ./modules/desktop.nix
        ./modules/disk.nix
      ];
    };

    ### Single chip boards ###

    # TODO create minimal aarch64 build to check minimal reasonable image size
    rpi4 = {
      ipAddress = "192.168.99.31";
      wgPublicKey = "sUUZ9eIfyjqdEDij7vGnOe3sFbbF/eHQqS0RMyWZU0c=";
      system = "aarch64-linux";
      extraModules = [
        "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
        ./modules/raspberry.nix
      ];
    };

    prusa = {
      ipAddress = "192.168.99.32";
      wgPublicKey = "jprPNJTX7OSXshr+SYanLjxyGdXH4ESHF+sAsUrxshk=";
      system = "aarch64-linux";
      extraModules = [
        "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
        ./modules/raspberry.nix
      ];
    };

    ### non-NixOS ###

    latitude = {
      ipAddress = "192.168.99.51";
      wgPublicKey = "ggj+uqF/vij5V+fA5r9GIv5YuT9hX7OBp+lAGYh5SyQ=";
      kind = "home-manager";
    };

    nokia = {
      ipAddress = "192.168.99.52";
      wgPublicKey = "HP+nPkrKwAxvmXjrI9yjsaGRMVXqt7zdcBGbD2ji83g=";
      kind = "wg-client";
    };

    ### NixOS installer ###

    iso = {
      ipAddress = "192.168.99.99";
      wgPublicKey = "Oy92wzxmvxteRQkjCmWmQDFfOevbby6qx/9ZDG2SMSs=";
      extraModules = [
        "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
      ];
    };
  };
}
