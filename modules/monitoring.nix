# Monitoring options for prometheus scrape target registration
# Services use this to self-register their metrics endpoints
{lib, ...}: let
  inherit (lib) mkOption types;
in {
  options.homelab.monitoring = {
    scrapeTargets = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          metricsPath = mkOption {
            type = types.str;
            description = "Path to the metrics endpoint";
            example = "/metrics/immich";
          };

          job = mkOption {
            type = types.str;
            description = "Prometheus job name for this target";
            example = "immich";
          };
        };
      });
      default = {};
      description = ''
        Prometheus scrape targets registered by this host.
        Services add their metrics endpoints here, and prometheus
        discovers them automatically from all hosts.
      '';
      example = {
        immich = {
          metricsPath = "/metrics/immich";
          job = "immich";
        };
        node = {
          metricsPath = "/metrics/node";
          job = "node";
        };
      };
    };
  };
}
