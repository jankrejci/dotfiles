# Flake-level options for homelab configuration
# These are used by hosts.nix, deploy.nix, and images.nix
{
  inputs,
  lib ? inputs.nixpkgs.lib,
  ...
}: let
  inherit (lib) mkOption types;
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
        };
      };
      description = "Global homelab configuration";
    };

    # Host configurations
    hosts = mkOption {
      type = types.attrsOf types.attrs;
      default = {};
      description = "Host configurations";
    };

    # Service configurations
    services = mkOption {
      type = types.attrsOf types.attrs;
      default = {};
      description = "Service configurations";
    };

    # Netbird groups and policies for API sync
    netbird = mkOption {
      type = types.submodule {
        options = {
          groups = mkOption {
            type = types.attrsOf (types.submodule {});
            default = {};
            description = "Netbird groups (names only, peers managed via dashboard)";
          };
          policies = mkOption {
            type = types.attrsOf (types.submodule {
              options = {
                description = mkOption {
                  type = types.str;
                  default = "";
                  description = "Policy description";
                };
                enabled = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Whether the policy is enabled";
                };
                rules = mkOption {
                  type = types.listOf (types.submodule {
                    options = {
                      name = mkOption {
                        type = types.str;
                        description = "Rule name";
                      };
                      description = mkOption {
                        type = types.str;
                        default = "";
                        description = "Rule description";
                      };
                      enabled = mkOption {
                        type = types.bool;
                        default = true;
                        description = "Whether the rule is enabled";
                      };
                      sources = mkOption {
                        type = types.listOf types.str;
                        description = "Source group names";
                      };
                      destinations = mkOption {
                        type = types.listOf types.str;
                        description = "Destination group names";
                      };
                      protocol = mkOption {
                        type = types.enum ["all" "tcp" "udp" "icmp"];
                        default = "all";
                        description = "Protocol to allow";
                      };
                      ports = mkOption {
                        type = types.listOf types.str;
                        default = [];
                        description = "Ports to allow (empty = all)";
                      };
                      bidirectional = mkOption {
                        type = types.bool;
                        default = false;
                        description = "Allow traffic in both directions";
                      };
                      action = mkOption {
                        type = types.enum ["accept" "drop"];
                        default = "accept";
                        description = "Action to take";
                      };
                    };
                  });
                  description = "Policy rules";
                };
              };
            });
            default = {};
            description = "Netbird policies to create";
          };
        };
      };
      default = {};
      description = "Netbird API configuration (groups and policies)";
    };
  };

  # NixOS-level options - kept for backwards compatibility
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

          # Homelab service configuration for this host.
          # This attrset is injected directly into the NixOS module system
          # and merges with homelab.* options defined in ../homelab/*.nix.
          # Also used by cross-host references (e.g. wireguard peers).
          homelab = mkOption {
            type = types.attrs;
            default = {};
            description = "Homelab service configuration (injected as homelab.*)";
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
