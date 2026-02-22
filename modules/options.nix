# NixOS-level homelab options
#
# - host: current host metadata from flake
# - hosts: all host definitions for cross-references
# - global: domain, peerDomain, adminEmails
# - services: shared service configuration
# - scrapeTargets, watchdogTargets, alerts, healthChecks: monitoring
{lib, ...}: let
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

      hostPubkey = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "SSH Ed25519 public key for agenix-rekey";
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

  # Service configuration submodule
  serviceModule = types.submodule {
    options = {
      port = mkOption {
        type = types.nullOr (types.either types.port (types.attrsOf types.port));
        default = null;
        description = "Service port or named port set";
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

  # Watchdog target submodule for external monitoring enrollment.
  # Services register here when watchdog = true, and the watchdog module
  # auto-generates up/down alerts for each registered target.
  watchdogTarget = types.submodule {
    options = {
      job = mkOption {
        type = types.str;
        description = "Prometheus job name to monitor";
      };

      host = mkOption {
        type = types.str;
        description = "Host running the service";
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

  # Dashboard entry for the homelab landing page.
  # Services with web UIs register here so the dashboard module
  # can auto-generate the landing page.
  dashboardEntry = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "Display name for the service";
      };

      url = mkOption {
        type = types.str;
        description = "Full URL to the service";
      };

      icon = mkOption {
        type = types.path;
        description = "Path to SVG icon file";
      };
    };
  };

  # Backup job submodule for borg backups
  backupJobModule = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "Backup job name, used in systemd unit and repo path";
      };

      paths = mkOption {
        type = types.listOf types.str;
        description = "Paths to back up";
      };

      excludes = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Paths to exclude from backup";
      };

      database = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "PostgreSQL database to dump before backup";
      };

      service = mkOption {
        type = types.str;
        description = "Systemd service to stop during restore";
      };

      hour = mkOption {
        type = types.int;
        default = 2;
        description = "Hour to run backups at. Remote runs at :00, local at :30.";
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

    # Watchdog targets registered by service modules.
    # The watchdog module collects targets from all hosts and auto-generates
    # up/down alerts for each enrolled service.
    watchdogTargets = mkOption {
      type = types.listOf watchdogTarget;
      default = [];
      description = "Services enrolled in external watchdog monitoring";
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

    # Dashboard entries registered by service modules.
    # Services with web UIs register here.
    # The dashboard module collects entries from all hosts.
    dashboardEntries = mkOption {
      type = types.listOf dashboardEntry;
      default = [];
      description = "Dashboard entries for the homelab landing page";
    };

    # Backup configuration.
    # Services register jobs via homelab.backup.jobs. The central backup module
    # collects jobs from all hosts using the cross-host pattern and generates
    # borgbackup configs, database dumps, restore scripts, alerts, and health checks.
    backup = {
      remote = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable remote backup to vpsfree server";
        };

        server = mkOption {
          type = types.str;
          default = "borg@vpsfree.nb.krejci.io";
          description = "SSH connection string for remote borg server";
        };

        repoBase = mkOption {
          type = types.str;
          default = "/var/lib/borg-repos";
          description = "Base path for borg repositories on remote server";
        };
      };

      local = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable local backup to on-disk repository";
        };

        repoBase = mkOption {
          type = types.str;
          default = "/var/lib/borg-repos";
          description = "Base path for local borg repositories";
        };
      };

      # Backup jobs registered by service modules.
      # The central backup module collects these from the current host only
      # and generates all necessary configuration.
      jobs = mkOption {
        type = types.listOf backupJobModule;
        default = [];
        description = "Backup jobs registered by service modules";
      };
    };
  };
}
