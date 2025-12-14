{
  lib,
  nixos-hardware,
  ...
}:
with lib; {
  options.hostConfig = mkOption {
    description = "A set of defined hosts";
    # Explicitly pass `name`
    type = types.attrsOf (types.submodule ({name, ...}: {
      options = {
        hostName = mkOption {
          type = types.str;
          # Use the attribute name (e.g., "vpsfree") as default
          default = name;
          description = "The hostname of the system.";
        };

        kind = mkOption {
          type = types.str;
          default = "nixos";
          description = "Host kind: nixos or installer";
        };

        isRpi = mkOption {
          type = types.bool;
          default = false;
          description = "Whether this is a Raspberry Pi host";
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

        services = mkOption {
          type = types.attrsOf (types.submodule {
            options.ip = mkOption {
              type = types.str;
              description = "IP address for the service";
            };
          });
          default = {};
          description = "Service definitions with IP addresses for internal DNS";
        };
      };
    }));
  };

  ### Servers ###
  config.hostConfig = {
    vpsfree = {
      services = {
        share.ip = "192.168.92.1";
      };
      extraModules = [
        ./modules/headless.nix
        ./modules/netbird-homelab.nix
        ./modules/acme.nix
        ./modules/immich-public-proxy.nix
        ./modules/vpsadminos.nix
      ];
    };

    thinkcenter = {
      device = "/dev/sda";
      swapSize = "8G";
      services = {
        immich.ip = "192.168.91.1";
        grafana.ip = "192.168.91.2";
        jellyfin.ip = "192.168.91.3";
        ntfy.ip = "192.168.91.4";
      };
      extraModules = [
        ./modules/headless.nix
        ./modules/netbird-homelab.nix
        ./modules/acme.nix
        ./modules/disk-tpm-encryption.nix
        ./modules/grafana.nix
        ./modules/health-check.nix
        ./modules/immich.nix
        ./modules/jellyfin.nix
        ./modules/loki.nix
        ./modules/ntfy.nix
        ./modules/prometheus.nix
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
        ./modules/netbird-user.nix
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
        ./modules/netbird-user.nix
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
        ./modules/netbird-user.nix
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
        ./modules/netbird-user.nix
        ./modules/disk-tpm-encryption.nix
        ./modules/desktop.nix
        ./modules/notebook.nix
      ];
    };

    ### Single chip boards ###

    # TODO create minimal aarch64 build to check minimal reasonable image size
    rpi4 = {
      isRpi = true;
      extraModules = [
        ./modules/raspberry.nix
        ./modules/netbird-homelab.nix
      ];
    };

    prusa = {
      isRpi = true;
      services = {
        octoprint.ip = "192.168.93.1";
        webcam.ip = "192.168.93.2";
      };
      extraModules = [
        ./modules/raspberry.nix
        ./modules/netbird-homelab.nix
        ./modules/acme.nix
        ./modules/octoprint.nix
      ];
    };

    ### NixOS installer ###

    iso = {
      kind = "installer";
    };
  };
}
