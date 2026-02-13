# Flake-level options for homelab configuration
#
# - global settings: domain, peerDomain, adminEmails
# - host definitions: hostName, system, device, swapSize
# - service definitions: port, subdomain, interface
{
  inputs,
  lib ? inputs.nixpkgs.lib,
  ...
}: let
  inherit (lib) mkOption types;

  # Host submodule shared by flake.hosts and homelab.hosts
  hostSubmodule = types.submodule ({name, ...}: {
    options = {
      hostName = mkOption {
        type = types.str;
        default = name;
        description = "Hostname for this machine";
      };

      system = mkOption {
        type = types.enum ["x86_64-linux" "aarch64-linux"];
        default = "x86_64-linux";
        description = "System architecture";
      };

      isRpi = mkOption {
        type = types.bool;
        default = false;
        description = "Whether this is a Raspberry Pi host";
      };

      kind = mkOption {
        type = types.enum ["nixos" "installer"];
        default = "nixos";
        description = "Type of host configuration";
      };

      device = mkOption {
        type = types.str;
        default = "/dev/sda";
        description = "Root disk device path";
      };

      swapSize = mkOption {
        type = types.str;
        default = "1G";
        description = "Swap partition size";
      };

      hostPubkey = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "SSH Ed25519 public key for agenix-rekey";
      };

      homelab = mkOption {
        type = types.attrs;
        default = {};
        description = "Homelab service configuration";
      };

      extraModules = mkOption {
        type = types.listOf types.deferredModule;
        default = [];
        description = "Additional NixOS modules for this host";
      };
    };
  });
in {
  options.flake = {
    # Global configuration
    global = mkOption {
      type = types.submodule {
        options = {
          domain = mkOption {
            type = types.str;
            description = "Base domain for all services";
          };
          peerDomain = mkOption {
            type = types.str;
            description = "VPN peer domain for internal access";
          };
          adminEmails = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Email addresses with admin access to services";
          };
        };
      };
      description = "Global homelab configuration";
    };

    # Host configurations
    hosts = mkOption {
      type = types.attrsOf hostSubmodule;
      default = {};
      description = "Host configurations";
    };

    # Service configurations
    services = mkOption {
      type = types.attrsOf types.attrs;
      default = {};
      description = "Service configurations";
    };
  };

  # NixOS-level options - kept for backwards compatibility
  options.homelab = {
    hosts = mkOption {
      type = types.attrsOf hostSubmodule;
      default = {};
      description = "Host configurations for the homelab";
    };

    services = mkOption {
      description = "Global service configuration";
      type = types.attrsOf (types.submodule {
        options = {
          port = mkOption {
            type = types.nullOr types.port;
            default = null;
            description = "Service port";
          };

          subdomain = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Subdomain for this service";
          };

          domain = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Domain for this service";
          };

          interface = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Network interface for firewall rules";
          };
        };
      });
      default = {};
    };
  };
}
