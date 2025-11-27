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

        extraDnsLabels = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Extra DNS labels for Netbird (for service aliases)";
        };
      };
    }));
  };

  ### Servers ###
  config.hosts = {
    vpsfree = {
      extraDnsLabels = ["share"];
      extraModules = [
        ./modules/acme.nix
        ./modules/immich-public-proxy.nix
        ./modules/vpsadminos.nix
      ];
    };

    thinkcenter = {
      device = "/dev/sda";
      swapSize = "8G";
      extraDnsLabels = ["immich" "grafana" "ntfy"];
      extraModules = [
        ./modules/acme.nix
        ./modules/disk-tpm-encryption.nix
        ./modules/grafana.nix
        ./modules/immich.nix
        ./modules/ntfy.nix
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
