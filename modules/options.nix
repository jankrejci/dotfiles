# NixOS-level homelab options
# These are set by the flake and consumed by other modules
{lib, ...}: let
  inherit (lib) mkOption types;

  # Service IP assignment submodule
  serviceIpModule = types.submodule {
    options.ip = mkOption {
      type = types.str;
      description = "IP address for this service";
    };
  };

  # Module enable flags submodule
  moduleEnableModule = types.submodule {
    options.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether this module is enabled";
    };
  };

  # Host configuration submodule
  hostModule = types.submodule {
    options = {
      hostName = mkOption {
        type = types.str;
        description = "Hostname";
      };

      system = mkOption {
        type = types.enum ["x86_64-linux" "aarch64-linux"];
        description = "System architecture";
      };

      isRpi = mkOption {
        type = types.bool;
        description = "Whether this is a Raspberry Pi";
      };

      kind = mkOption {
        type = types.enum ["nixos" "installer"];
        description = "Type of host";
      };

      device = mkOption {
        type = types.str;
        description = "Root disk device";
      };

      swapSize = mkOption {
        type = types.str;
        description = "Swap partition size";
      };

      services = mkOption {
        type = types.attrsOf serviceIpModule;
        default = {};
        description = "Service IP assignments";
      };

      modules = mkOption {
        type = types.attrsOf moduleEnableModule;
        default = {};
        description = "Module enable flags";
      };

      extraModules = mkOption {
        type = types.listOf types.unspecified;
        default = [];
        description = "Extra NixOS modules";
      };

      # For prometheus discovery: scrape targets registered by this host
      scrapeTargets = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            metricsPath = mkOption {
              type = types.str;
              description = "Path to metrics endpoint";
            };
            job = mkOption {
              type = types.str;
              description = "Prometheus job name";
            };
          };
        });
        default = {};
        description = "Prometheus scrape targets for this host";
      };
    };
  };

  # Service configuration submodule
  serviceModule = types.submodule {
    options = {
      port = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "Service port";
      };

      subdomain = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Service subdomain";
      };

      domain = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Service domain";
      };

      interface = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Network interface";
      };
    };
  };
in {
  options.homelab = {
    # Current host configuration
    host = mkOption {
      type = hostModule;
      description = "Configuration for the current host";
    };

    # All hosts in the homelab
    hosts = mkOption {
      type = types.attrsOf hostModule;
      default = {};
      description = "All host configurations for prometheus discovery";
    };

    # Global service configuration
    services = mkOption {
      type = types.attrsOf serviceModule;
      default = {};
      description = "Global service configuration";
    };
  };
}
