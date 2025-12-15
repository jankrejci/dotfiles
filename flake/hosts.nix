# nixosConfigurations output using homelab options
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
      services = {
        share.ip = "192.168.92.1";
      };
      extraModules = [
        ../modules/headless.nix
        ../modules/netbird-homelab.nix
        ../modules/acme.nix
        ../modules/immich-public-proxy.nix
        ../modules/vpsadminos.nix
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
      modules = {
        immich.enable = true;
        grafana.enable = true;
        prometheus.enable = true;
        ntfy.enable = true;
      };
      extraModules = [
        ../modules/headless.nix
        ../modules/netbird-homelab.nix
        ../modules/acme.nix
        ../modules/disk-tpm-encryption.nix
        ../modules/health-check.nix
        ../modules/jellyfin.nix
        ../modules/loki.nix
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
      services = {
        octoprint.ip = "192.168.93.1";
        webcam.ip = "192.168.93.2";
      };
      modules = {
        octoprint.enable = true;
      };
      extraModules = [
        ../modules/raspberry.nix
        ../modules/netbird-homelab.nix
        ../modules/acme.nix
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

  # Service configuration
  services = {
    https = {
      port = 443;
    };

    metrics = {
      port = 9999;
    };

    netbird = {
      interface = "nb-homelab";
    };

    grafana = {
      port = 3000;
      subdomain = "grafana";
    };

    prometheus = {
      port = 9090;
    };

    loki = {
      port = 3100;
    };

    promtail = {
      port = 9080;
    };

    immich = {
      port = 2283;
      subdomain = "immich";
    };

    ntfy = {
      port = 2586;
      subdomain = "ntfy";
    };

    jellyfin = {
      port = 8096;
      subdomain = "jellyfin";
    };

    octoprint = {
      port = 5000;
      subdomain = "octoprint";
    };

    immich-public-proxy = {
      port = 2283;
      subdomain = "share";
      interface = "venet0";
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
    ../modules # Single import point for all homelab modules
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
      # Inject homelab configuration
      ({...}: {
        # Current host - add hostName for modules that need it
        homelab.host = host // {hostName = host.hostName or hostName;};
        # All hosts for prometheus discovery
        homelab.hosts = hosts;
        # Global configuration
        homelab.global = global;
        # Service configuration
        homelab.services = services;

        # Wire up enable flags from host config to homelab modules
        homelab.immich.enable = host.modules.immich.enable or false;
        homelab.grafana.enable = host.modules.grafana.enable or false;
        homelab.prometheus.enable = host.modules.prometheus.enable or false;
        homelab.ntfy.enable = host.modules.ntfy.enable or false;
        homelab.octoprint.enable = host.modules.octoprint.enable or false;
      })
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
