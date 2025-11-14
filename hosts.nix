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
      extraModules = [
        ./modules/grafana.nix
        ./modules/vpsadminos.nix
        ./modules/dnsmasq.nix
      ];
    };

    thinkcenter = {
      device = "/dev/sda";
      swapSize = "8G";
      extraModules = [
        ./modules/disk-tpm-encryption.nix
        ./modules/immich.nix
      ];
    };

    ### Desktops ###

    e470 = {
      device = "/dev/sda";
      swapSize = "8G";
      extraModules = [
        nixos-hardware.nixosModules.lenovo-thinkpad-e470
        ./users/jkr.nix
        ./users/paja.nix
        ./modules/disk-tpm-encryption.nix
        ./modules/desktop.nix
        ./modules/notebook.nix
      ];
    };

    optiplex = {
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
      device = "/dev/nvme0n1";
      swapSize = "8G";
      extraModules = [
        nixos-hardware.nixosModules.framework-13-7040-amd
        ./users/jkr.nix
        ./users/paja.nix
        ./modules/disk-tpm-encryption.nix
        ./modules/desktop.nix
        ./modules/notebook.nix
        ./modules/eset-agent.nix
      ];
    };

    t14 = {
      device = "/dev/nvme0n1";
      swapSize = "8G";
      extraModules = [
        nixos-hardware.nixosModules.lenovo-thinkpad-t14-amd-gen1
        ./users/jkr.nix
        ./users/paja.nix
        ./modules/disk-tpm-encryption.nix
        ./modules/desktop.nix
        ./modules/notebook.nix
      ];
    };

    ### Single chip boards ###

    # TODO create minimal aarch64 build to check minimal reasonable image size
    rpi4 = {
      system = "aarch64-linux";
      extraModules = [
        ./modules/raspberry.nix
      ];
    };

    prusa = {
      system = "aarch64-linux";
      extraModules = [
        ./modules/raspberry.nix
      ];
    };

    ### NixOS installer ###

    iso = {
      kind = "installer";
    };
  };
}
