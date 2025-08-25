{
  lib,
  nixos-hardware,
  ...
}:
with lib; {
  options.hosts = mkOption {
    description = "A set of defined hosts";
    # Explicitly pass `name`
    type = types.attrsOf (types.submodule ({
      config,
      name,
      ...
    }: {
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
          # Use nix path ./hosts to properly evaluate the full path
          default = builtins.readFile (toString ./hosts + "/${config.hostName}/wg-key.pub");
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

        device = mkOption {
          type = types.str;
          description = "System disk device";
        };

        swapSize = mkOption {
          type = types.str;
          default = "1G";
          description = "Size of the swap partition";
        };

        extraModules = mkOption {
          type = types.listOf types.path;
          default = [];
          description = "Extra NixOS modules to include";
        };
      };
    }));
  };

  ### Servers ###
  config.hosts = {
    vpsfree = {
      ipAddress = "192.168.99.1";
      extraModules = [
        ./modules/grafana.nix
        ./modules/vpsadminos.nix
        ./modules/wg-server.nix
      ];
    };

    thinkcenter = {
      ipAddress = "192.168.99.2";
      device = "/dev/sda";
      swapSize = "8G";
      extraModules = [
        ./modules/disk-tpm-encryption.nix
      ];
    };

    ### Desktops ###

    thinkpad = {
      ipAddress = "192.168.99.21";
      device = "/dev/sda";
      swapSize = "8G";
      extraModules = [
        nixos-hardware.nixosModules.lenovo-thinkpad-e470
        ./users/jkr.nix
        ./users/paja.nix
        ./modules/disk-tpm-encryption.nix
        ./modules/desktop.nix
      ];
    };

    optiplex = {
      ipAddress = "192.168.99.22";
      device = "/dev/sda";
      swapSize = "8G";
      extraModules = [
        ./users/jkr.nix
        ./users/paja.nix
        ./modules/disk-password-encryption.nix
        ./modules/desktop.nix
      ];
    };

    framework = {
      ipAddress = "192.168.99.23";
      device = "/dev/nvme0n1";
      swapSize = "8G";
      extraModules = [
        nixos-hardware.nixosModules.framework-13-7040-amd
        ./users/jkr.nix
        ./users/paja.nix
        ./modules/disk-tpm-encryption.nix
        ./modules/desktop.nix
        ./modules/eset-agent.nix
      ];
    };

    t14 = {
      ipAddress = "192.168.99.24";
      device = "/dev/nvme0n1";
      swapSize = "8G";
      extraModules = [
        nixos-hardware.nixosModules.lenovo-thinkpad-t14-amd-gen1
        ./users/jkr.nix
        ./users/paja.nix
        ./modules/disk-tpm-encryption.nix
        ./modules/desktop.nix
      ];
    };

    ### Single chip boards ###

    # TODO create minimal aarch64 build to check minimal reasonable image size
    rpi4 = {
      ipAddress = "192.168.99.31";
      system = "aarch64-linux";
      extraModules = [
        ./modules/raspberry.nix
      ];
    };

    prusa = {
      ipAddress = "192.168.99.32";
      system = "aarch64-linux";
      extraModules = [
        ./modules/raspberry.nix
      ];
    };

    ### non-NixOS ###

    nokia = {
      ipAddress = "192.168.99.52";
      kind = "wg-client";
    };

    ### NixOS installer ###

    iso = {
      ipAddress = "192.168.99.99";
      kind = "installer";
    };
  };
}
