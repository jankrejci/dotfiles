# NixOS-level homelab options
# These are set by the flake and consumed by other modules
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types;

  # Host configuration submodule
  hostModule = types.submodule ({name, ...}: {
    options = {
      hostName = mkOption {
        type = types.str;
        default = name;
        description = "Hostname";
      };

      system = mkOption {
        type = types.enum ["x86_64-linux" "aarch64-linux"];
        default = "x86_64-linux";
        description = "System architecture";
      };

      isRpi = mkOption {
        type = types.bool;
        default = false;
        description = "Whether this is a Raspberry Pi";
      };

      kind = mkOption {
        type = types.enum ["nixos" "installer"];
        default = "nixos";
        description = "Type of host";
      };

      device = mkOption {
        type = types.str;
        default = "/dev/sda";
        description = "Root disk device";
      };

      swapSize = mkOption {
        type = types.str;
        default = "1G";
        description = "Swap partition size";
      };

      # Homelab service configuration for this host.
      # Injected into NixOS module system and merges with homelab/*.nix options.
      homelab = mkOption {
        type = types.attrs;
        default = {};
        description = "Homelab service configuration";
      };

      extraModules = mkOption {
        type = types.listOf types.unspecified;
        default = [];
        description = "Extra NixOS modules";
      };

      # Alert rules for this host, collected by prometheus
      alerts = mkOption {
        type = types.attrsOf (types.listOf alertRule);
        default = {};
        description = "Alert rules grouped by category";
      };
    };
  });

  # Secret declaration for inject-secrets script.
  # Services declare what secrets they need and how to handle them.
  secretModule = types.submodule {
    options = {
      generate = mkOption {
        type = types.enum ["token" "ask"];
        description = "How to generate the secret value: token = random, ask = prompt user";
      };

      handler = mkOption {
        type = types.package;
        description = "Script that receives secret on stdin and writes it to the right place";
      };

      username = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Username or client ID for registration with central service";
      };

      register = mkOption {
        type = types.nullOr (types.enum ["ntfy" "dex"]);
        default = null;
        description = "Central service to register with, if any";
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

      subnet = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Network subnet for access control";
      };
    };
  };
  # Global configuration submodule
  globalModule = types.submodule {
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

  # Alert rule submodule for prometheus
  alertRule = types.submodule {
    options = {
      alert = mkOption {
        type = types.str;
        description = "Alert name";
      };

      expr = mkOption {
        type = types.str;
        description = "PromQL expression";
      };

      for = mkOption {
        type = types.str;
        default = "5m";
        description = "Duration before alert fires";
      };

      labels = mkOption {
        type = types.attrsOf types.str;
        default = {};
        description = "Alert labels";
      };

      annotations = mkOption {
        type = types.attrsOf types.str;
        default = {};
        description = "Alert annotations";
      };
    };
  };

  # Scrape target submodule for prometheus
  scrapeTarget = types.submodule {
    options = {
      job = mkOption {
        type = types.str;
        description = "Prometheus job name";
      };

      metricsPath = mkOption {
        type = types.str;
        description = "Path to metrics endpoint";
      };
    };
  };

  # Health check submodule for distributed health checks
  healthCheckModule = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "Display name for this health check";
      };

      script = mkOption {
        type = types.package;
        description = "Executable script that returns 0 on success, non-zero on failure";
      };

      timeout = mkOption {
        type = types.int;
        default = 30;
        description = "Timeout in seconds";
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

    # Global configuration
    global = mkOption {
      type = globalModule;
      description = "Global homelab configuration";
    };

    # Service configuration
    services = mkOption {
      type = types.attrsOf serviceModule;
      default = {};
      description = "Service configuration";
    };

    # Service IPs for the services dummy interface.
    # Each service module registers its IPs here.
    # networking.nix collects all IPs and configures the interface.
    serviceIPs = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "IPs to add to services dummy interface";
    };

    # Scrape targets for prometheus.
    # Each service module registers its metrics endpoints here.
    # Prometheus collects from all hosts and generates scrape configs.
    scrapeTargets = mkOption {
      type = types.listOf scrapeTarget;
      default = [];
      description = "Prometheus scrape targets for this host";
    };

    # Alert rules grouped by service name.
    # Each service module contributes its alerts here.
    # Prometheus collects all groups into rule files.
    alerts = mkOption {
      type = types.attrsOf (types.listOf alertRule);
      default = {};
      description = "Alert rules grouped by service";
    };

    # Health checks registered by service modules.
    # Each service module contributes its health checks here.
    # The health-check module iterates over all checks and runs them.
    healthChecks = mkOption {
      type = types.listOf healthCheckModule;
      default = [];
      description = "Health checks registered by service modules";
    };

    # Secret declarations for inject-secrets script.
    # Services declare secrets they need with a local handler.
    # If the secret needs registration with a central service, specify register and username.
    secrets = mkOption {
      type = types.attrsOf secretModule;
      default = {};
      description = "Secret declarations for inject-secrets script";
    };
  };

  # Generate JSON manifest for inject-secrets script when secrets are declared
  config = lib.mkIf (config.homelab.secrets != {}) {
    system.build.secrets-manifest = pkgs.writeText "secrets.json" (builtins.toJSON config.homelab.secrets);
  };
}
