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
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIcON6y4kzRaoHdLDUGf25OBqCvD1WY8iM1t2jUikaPf";
      homelab = {
        acme.enable = true;
        healthCheck = {
          enable = true;
          ntfyUrl = "https://ntfy.krejci.io";
          ntfyTopic = "system-health";
        };
        watchdog = {
          enable = true;
          ip = "192.168.92.2";
          email = {
            from = "admin@krejci.io";
            to = "admin@krejci.io";
          };
        };
        netbird-signal = {
          enable = true;
          ip = "192.168.92.3";
          interface = "venet0";
          managementHost = "thinkcenter";
        };
        tunnel = {
          enable = true;
          ip = "192.168.99.2";
          server = true;
          peers = ["thinkcenter"];
          proxy = {
            enable = true;
            domains = ["share.krejci.io" "dex.krejci.io"];
          };
        };
      };
      extraModules = [
        ../modules/headless.nix
        ../modules/netbird-homelab.nix
        ../modules/vpsadminos.nix
      ];
    };

    thinkcenter = {
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPEK336HnGuQlJl7d3XPw3zw4AhYGDLxx50ZbBuD+nu0";
      device = "/dev/sda";
      swapSize = "8G";
      homelab = {
        # Shared infrastructure
        nginx.enable = true;
        postgresql.enable = true;
        redis.enable = true;
        # Services
        acme.enable = true;
        healthCheck = {
          enable = true;
          ntfyUrl = "https://ntfy.krejci.io";
          ntfyTopic = "system-health";
        };
        dex = {
          enable = true;
          ip = "192.168.91.7";
        };
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
        memos = {
          enable = true;
          ip = "192.168.91.6";
        };
        netbird-server = {
          enable = true;
          ip = "192.168.91.9";
        };
        ntfy = {
          enable = true;
          ip = "192.168.91.4";
          watchdog = true;
        };
        printer = {
          enable = true;
          ip = "192.168.91.5";
        };
        immich-public-proxy = {
          enable = true;
          ip = "192.168.91.10";
          tunnel = true;
        };
        prometheus = {
          enable = true;
          ip = "192.168.91.8";
          watchdog = true;
        };
        tunnel = {
          enable = true;
          ip = "192.168.99.1";
          peers = ["vpsfree"];
        };
        backup = {
          remote.enable = true;
          local.enable = true;
        };
      };
      extraModules = [
        ../modules/headless.nix
        ../modules/netbird-homelab.nix
        ../modules/disk-tpm-encryption.nix
      ];
    };

    ### Desktops ###

    e470 = {
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBuVvVmSeaoUPKqiPqxwJEWDgdClxQpp6KjttCy/kFIq";
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
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBmzspcGU4YVye6UtIB0fRPoonamNPrdGqEvyXm9Gbg5";
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
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGmfq9F+krusOKm33U/uLgCfspYeno4sGYkGQQsb9VG1";
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
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDnncYKui8LgDke6oO3gntbH1iFkp2K/yyLx3TCjVY1g";
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
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAbaTQOMDT3HYGiFVucqr4r1VbrwtMgltvnOeUNYbHMh";
      system = "aarch64-linux";
      isRpi = true;
      extraModules = [
        ../modules/raspberry.nix
        ../modules/netbird-homelab.nix
      ];
    };

    prusa = {
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHyOwwhHylbrE+HztW0BaCOHypV73ESOIUgUJl/K/OvF";
      system = "aarch64-linux";
      isRpi = true;
      homelab = {
        acme.enable = true;
        octoprint = {
          enable = true;
          ip = "192.168.93.1";
        };
        webcam.enable = true;
      };
      extraModules = [
        ../modules/raspberry.nix
        ../modules/netbird-homelab.nix
      ];
    };

    rak2245 = {
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOBKrxal9ON2M+bbKwBrDNQLi8jgadibM7WN51fYO6Ng";
      system = "aarch64-linux";
      isRpi = true;
      homelab = {
        lorawan-gateway = {
          enable = true;
          eui = "B827EBFFFEC5ECE3";
          gnss.enable = true;
        };
      };
      extraModules = [
        ../modules/raspberry.nix
        ../modules/netbird-homelab.nix
      ];
    };

    ### NixOS installer ###

    # ISO uses a static host key so agenix can decrypt secrets at build time.
    # The private key is embedded in the ISO in plain text.
    #
    # Security model: The only secret is admin-password-hash, a generic
    # fallback password for emergency access. ISOs are ephemeral install media
    # and do not contain sensitive service credentials. If the admin password
    # is compromised, rotate it and rebuild the ISO with the new hash.
    iso = {
      kind = "installer";
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGm0+8CuZ8AV3EsZ5I4T4kPeQGBG7Z7pcEg4fhnVr9ri";
    };
  };

  # Global configuration
  global = {
    domain = "krejci.io";
    peerDomain = "nb.krejci.io";
    adminEmails = ["krejcijan@protonmail.com"];
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

    # Overlay network uses CGNAT range (RFC 6598) to avoid conflicts with
    # RFC 1918 private ranges on LANs. Same approach as Tailscale.
    # The subnet is stored in the management database at account creation
    # and cannot be changed via config files, only via REST API or dashboard.
    netbird = {
      interface = "nb0";
      port = {
        nb = 51820;
        relay = 33080;
        signal = 8012;
      };
      subnet = "100.76.0.0/16";
    };
  };

  # Shared module builders
  shared = import ./lib.nix {inherit inputs lib hosts global services;};

  # Filter by kind
  nixosHosts = lib.filterAttrs (_: h: (h.kind or "nixos") == "nixos") hosts;
  rpiHosts = lib.filterAttrs (_: h: h.isRpi or false) nixosHosts;
  regularHosts = lib.filterAttrs (_: h: !(h.isRpi or false)) nixosHosts;

  # Create nixosConfiguration for regular x86_64 hosts
  mkSystem = hostName: host:
    withSystem "x86_64-linux" ({pkgs, ...}:
      lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs;
        };
        modules =
          shared.baseModules
          ++ shared.mkModulesList {inherit hostName host;}
          ++ [({...}: {nixpkgs.pkgs = pkgs;})];
      });

  # Create nixosConfiguration for RPi hosts.
  # Uses lib.nixosSystem with our nixpkgs so standard package hashes match
  # cache.nixos.org. The inject-overlays module adds RPi kernel, firmware,
  # and vendor packages on top.
  mkRpiSystem = hostName: host:
    lib.nixosSystem {
      specialArgs = {
        inherit inputs;
        inherit (inputs) nixos-raspberrypi;
      };
      modules =
        shared.baseModules
        ++ shared.mkModulesList {inherit hostName host;}
        ++ [
          inputs.nixos-raspberrypi.lib.inject-overlays
          inputs.nixos-raspberrypi.nixosModules.nixpkgs-rpi
          ({...}: {
            # Override the x86_64-linux default from common.nix
            nixpkgs.hostPlatform = "aarch64-linux";
            nixpkgs.overlays = [config.flake.overlays.unstableOverlay];
          })
        ];
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
