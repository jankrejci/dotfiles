# nixosConfigurations output using homelab options
#
# Host definitions use a simple pattern:
# - Standard NixOS options (device, swapSize) go at the top level
# - Service configuration goes under `homelab` and is injected directly
#   into the NixOS module system (no manual wiring needed)
# - Extra NixOS modules go in `extraModules`
#
# The `homelab` attrset maps directly to homelab.* NixOS options defined
# in ../homelab/*.nix modules. Each module defines its own options with
# sensible defaults. Host-specific values (IPs, enable flags) override them.
#
# Example:
#   myhost = {
#     device = "/dev/sda";
#     homelab = {
#       grafana = { enable = true; ip = "192.168.1.1"; };
#       prometheus.enable = true;
#     };
#     extraModules = [ ../modules/headless.nix ];
#   };
{
  inputs,
  config,
  withSystem,
  ...
}: let
  lib = inputs.nixpkgs.lib;

  # Host definitions
  hosts = {
    ### Servers ###

    vpsfree = {
      homelab = {
        acme.enable = true;
        immich-public-proxy = {
          enable = true;
          ip = "192.168.92.1";
          interface = "venet0";
        };
        wireguard = {
          enable = true;
          ip = "192.168.99.2";
          server = true;
          peers = ["thinkcenter"];
        };
      };
      extraModules = [
        ../modules/headless.nix
        ../modules/netbird-homelab.nix
        ../modules/vpsadminos.nix
      ];
    };

    thinkcenter = {
      device = "/dev/sda";
      swapSize = "8G";
      homelab = {
        acme.enable = true;
        grafana = {
          enable = true;
          ip = "192.168.91.2";
        };
        immich = {
          enable = true;
          ip = "192.168.91.1";
        };
        jellyfin = {
          enable = true;
          ip = "192.168.91.3";
        };
        loki.enable = true;
        ntfy = {
          enable = true;
          ip = "192.168.91.4";
        };
        prometheus.enable = true;
        wireguard = {
          enable = true;
          ip = "192.168.99.1";
          peers = ["vpsfree"];
        };
      };
      extraModules = [
        ../modules/headless.nix
        ../modules/netbird-homelab.nix
        ../modules/disk-tpm-encryption.nix
        ../modules/health-check.nix
      ];
    };

    ### Desktops ###

    e470 = {
      device = "/dev/sda";
      swapSize = "8G";
      extraModules = [
        inputs.nixos-hardware.nixosModules.lenovo-thinkpad-e470
        ../users/jkr.nix
        ../users/paja.nix
        ../modules/netbird-user.nix
        ../modules/disk-tpm-encryption.nix
        ../modules/desktop.nix
        ../modules/notebook.nix
      ];
    };

    optiplex = {
      device = "/dev/sda";
      swapSize = "8G";
      extraModules = [
        ../users/jkr.nix
        ../users/paja.nix
        ../modules/netbird-user.nix
        ../modules/disk-password-encryption.nix
        ../modules/desktop.nix
      ];
    };

    framework = {
      device = "/dev/nvme0n1";
      swapSize = "8G";
      extraModules = [
        inputs.nixos-hardware.nixosModules.framework-13-7040-amd
        ../users/jkr.nix
        ../users/paja.nix
        ../modules/netbird-user.nix
        ../modules/disk-tpm-encryption.nix
        ../modules/desktop.nix
        ../modules/notebook.nix
        ../modules/eset-agent.nix
      ];
    };

    t14 = {
      device = "/dev/nvme0n1";
      swapSize = "8G";
      extraModules = [
        inputs.nixos-hardware.nixosModules.lenovo-thinkpad-t14-amd-gen1
        ../users/jkr.nix
        ../users/paja.nix
        ../modules/netbird-user.nix
        ../modules/disk-tpm-encryption.nix
        ../modules/desktop.nix
        ../modules/notebook.nix
      ];
    };

    ### Raspberry Pi ###

    rpi4 = {
      system = "aarch64-linux";
      isRpi = true;
      extraModules = [
        ../modules/raspberry.nix
        ../modules/netbird-homelab.nix
      ];
    };

    prusa = {
      system = "aarch64-linux";
      isRpi = true;
      homelab = {
        acme.enable = true;
        octoprint = {
          enable = true;
          ip = "192.168.93.1";
          webcamIp = "192.168.93.2";
        };
      };
      extraModules = [
        ../modules/raspberry.nix
        ../modules/netbird-homelab.nix
      ];
    };

    rak2245 = {
      system = "aarch64-linux";
      isRpi = true;
      homelab = {
        lorawan-gateway.enable = true;
      };
      extraModules = [
        ../modules/raspberry.nix
        ../modules/netbird-homelab.nix
      ];
    };

    ### NixOS installer ###

    iso = {
      kind = "installer";
    };
  };

  # Global configuration
  global = {
    domain = "krejci.io";
    peerDomain = "nb.krejci.io";
  };

  # Shared service configuration
  # Service-specific ports and subdomains are now defined in module defaults
  services = {
    https = {
      port = 443;
    };

    metrics = {
      port = 9999;
    };

    netbird = {
      interface = "nb0";
      port = 51820;
    };
  };

  # Filter by kind
  nixosHosts = lib.filterAttrs (_: h: (h.kind or "nixos") == "nixos") hosts;
  rpiHosts = lib.filterAttrs (_: h: h.isRpi or false) nixosHosts;
  regularHosts = lib.filterAttrs (_: h: !(h.isRpi or false)) nixosHosts;

  # Common base modules for all hosts
  baseModules = [
    inputs.home-manager.nixosModules.home-manager
    inputs.disko.nixosModules.disko
    inputs.nix-flatpak.nixosModules.nix-flatpak
    ../modules # Base system modules
    ../homelab # Service modules with enable pattern
    ../users/admin.nix
  ];

  # Create modules list for a host
  mkModulesList = hostName: host: let
    hostConfigFile = ../hosts/${hostName}.nix;
    hasHostConfig = builtins.pathExists hostConfigFile;
  in
    baseModules
    ++ lib.optional hasHostConfig hostConfigFile
    ++ host.extraModules or []
    ++ [
      # Inject shared homelab configuration
      ({...}: {
        # Current host metadata for modules that need device, swapSize, etc.
        # Excludes homelab key - use config.homelab.X for service config instead.
        homelab.host = (builtins.removeAttrs host ["homelab"]) // {hostName = host.hostName or hostName;};
        # All hosts for cross-host references like wireguard peers.
        # Includes homelab key so modules can access hosts.X.homelab.Y
        homelab.hosts = hosts;
        # Global config: domain, peerDomain
        homelab.global = global;
        # Shared service config: https.port, metrics.port, netbird.*
        homelab.services = services;
      })
      # Inject host-specific homelab config directly into NixOS module system.
      # The attrset merges with option definitions from ../homelab/*.nix modules.
      ({...}: {homelab = host.homelab or {};})
    ];

  # Create nixosConfiguration for regular x86_64 hosts
  mkSystem = hostName: host:
    withSystem "x86_64-linux" ({pkgs, ...}:
      lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs;};
        modules =
          mkModulesList hostName host
          ++ [({...}: {nixpkgs.pkgs = pkgs;})];
      });

  # Cached aarch64 packages for RPi overlay
  cachedPkgs-aarch64 = import inputs.nixpkgs {
    system = "aarch64-linux";
    config.allowUnfree = true;
  };

  # Create nixosConfiguration for RPi hosts
  mkRpiSystem = hostName: host:
    inputs.nixos-raspberrypi.lib.nixosSystem {
      specialArgs = {
        inherit inputs cachedPkgs-aarch64;
        inherit (inputs) nixos-raspberrypi;
      };
      modules = mkModulesList hostName host;
    };
in {
  # Export configuration for other flake modules
  flake.hosts = hosts;
  flake.global = global;
  flake.services = services;

  flake.nixosConfigurations =
    lib.mapAttrs mkSystem regularHosts
    // lib.mapAttrs mkRpiSystem rpiHosts;
}
