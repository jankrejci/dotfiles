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

  # Service configuration
  services = {
    global = {
      domain = "krejci.io";
    };

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

  # Normalize host config with defaults
  normalizeHost = name: cfg: {
    hostName = cfg.hostName or name;
    system = cfg.system or "x86_64-linux";
    isRpi = cfg.isRpi or false;
    kind = cfg.kind or "nixos";
    device = cfg.device or "/dev/sda";
    swapSize = cfg.swapSize or "1G";
    services = cfg.services or {};
    modules = cfg.modules or {};
    extraModules = cfg.extraModules or [];
  };

  # Normalized hosts
  normalizedHosts = lib.mapAttrs normalizeHost hosts;

  # Filter by kind
  nixosHosts = lib.filterAttrs (_: h: h.kind == "nixos") normalizedHosts;
  rpiHosts = lib.filterAttrs (_: h: h.isRpi) nixosHosts;
  regularHosts = lib.filterAttrs (_: h: !h.isRpi) nixosHosts;

  # Common base modules for all hosts
  baseModules = [
    inputs.home-manager.nixosModules.home-manager
    inputs.disko.nixosModules.disko
    inputs.nix-flatpak.nixosModules.nix-flatpak
    ../modules # Single import point for all homelab modules
    ../users/admin.nix
  ];

  # Create modules list for a host
  mkModulesList = hostName: hostCfg: let
    hostConfigFile = ../hosts/${hostName}.nix;
    hasHostConfig = builtins.pathExists hostConfigFile;
  in
    baseModules
    ++ lib.optional hasHostConfig hostConfigFile
    ++ hostCfg.extraModules
    ++ [
      # Inject homelab configuration
      ({...}: {
        # Current host
        homelab.host = hostCfg;
        # All hosts for prometheus discovery
        homelab.hosts = normalizedHosts;
        # Global service configuration
        homelab.services = services;

        # Wire up enable flags from host config to homelab modules
        homelab.immich.enable = hostCfg.modules.immich.enable or false;
        homelab.grafana.enable = hostCfg.modules.grafana.enable or false;
        homelab.prometheus.enable = hostCfg.modules.prometheus.enable or false;
        homelab.ntfy.enable = hostCfg.modules.ntfy.enable or false;
        homelab.octoprint.enable = hostCfg.modules.octoprint.enable or false;
      })
    ];

  # Create nixosConfiguration for regular x86_64 hosts
  mkSystem = hostName: hostCfg:
    withSystem "x86_64-linux" ({pkgs, ...}:
      lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs;};
        modules =
          mkModulesList hostName hostCfg
          ++ [({...}: {nixpkgs.pkgs = pkgs;})];
      });

  # Cached aarch64 packages for RPi overlay
  cachedPkgs-aarch64 = import inputs.nixpkgs {
    system = "aarch64-linux";
    config.allowUnfree = true;
  };

  # Create nixosConfiguration for RPi hosts
  mkRpiSystem = hostName: hostCfg:
    inputs.nixos-raspberrypi.lib.nixosSystem {
      specialArgs = {
        inherit inputs cachedPkgs-aarch64;
        inherit (inputs) nixos-raspberrypi;
      };
      modules = mkModulesList hostName hostCfg;
    };
in {
  # Export hosts and services for external use
  flake.hosts = normalizedHosts;
  flake.services = services;

  flake.nixosConfigurations =
    lib.mapAttrs mkSystem regularHosts
    // lib.mapAttrs mkRpiSystem rpiHosts;
}
