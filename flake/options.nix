# Custom flake-level options for homelab configuration
# These are internal options used to configure nixosConfigurations, not flake outputs
{
  inputs,
  lib ? inputs.nixpkgs.lib,
  ...
}: let
  inherit (lib) mkOption types;
in {
  # Internal options for homelab configuration
  # These are used by flake/hosts.nix to generate nixosConfigurations
  options.homelab = {
    hosts = mkOption {
      description = "Host configurations for the homelab";
      type = types.attrsOf (types.submodule ({name, ...}: {
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

          # Service IPs assigned to this host
          services = mkOption {
            type = types.attrsOf (types.submodule {
              options.ip = mkOption {
                type = types.str;
                description = "IP address for this service on this host";
              };
            });
            default = {};
            description = "Service IP assignments for this host";
          };

          # Module enable flags
          modules = mkOption {
            type = types.attrsOf (types.submodule {
              options.enable = mkOption {
                type = types.bool;
                default = false;
                description = "Whether to enable this module";
              };
            });
            default = {};
            description = "Module enable flags";
          };

          # Extra NixOS modules to include
          extraModules = mkOption {
            type = types.listOf types.deferredModule;
            default = [];
            description = "Additional NixOS modules for this host";
          };
        };
      }));
      default = {};
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
