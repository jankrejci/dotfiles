# Prusa printer bridge to Obico
#
# - drives the printer through the serial bridge on the printer host
# - reports status and temperatures to Obico and takes pause, resume and cancel
# - uploads snapshots cut from the printer host's H.264 stream for AI detection
# - /status JSON and /metrics on localhost for debugging and prometheus
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.prusa-obico;
  global = config.homelab.global;
  package = pkgs.callPackage ../pkgs/prusa-obico.nix {};

  # Ports come from the printer host so the two sides cannot drift apart.
  printerConfig = inputs.self.nixosConfigurations.${cfg.printerHost}.config.homelab;
  printerAddress = "${cfg.printerHost}.${global.peerDomain}";
in {
  options.homelab.prusa-obico = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the Prusa printer bridge to Obico";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9188;
      description = "Port for the /status and /metrics endpoints";
    };

    printerHost = lib.mkOption {
      type = lib.types.str;
      default = "prusa";
      description = "Host running the serial bridge and webcam for the printer";
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets.prusa-obico-token.rekeyFile = ../secrets/prusa-obico-token.age;

    systemd.services.prusa-obico = {
      description = "Prusa printer bridge to Obico";
      wants = ["network-online.target"];
      after = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      environment = {
        PRUSA_OBICO_PRINTER = "${printerAddress}:${toString printerConfig.serial-bridge.port.proxy}";
        PRUSA_OBICO_VIDEO_URL = "https://${printerAddress}/video.mkv";
        PRUSA_OBICO_FFMPEG = lib.getExe pkgs.ffmpeg-headless;
        PRUSA_OBICO_LISTEN = "127.0.0.1:${toString cfg.port}";
      };
      serviceConfig = {
        Type = "notify";
        # The token file is passed as a credential, which systemd reads as
        # root, so the dynamic user needs no access to the agenix secret.
        LoadCredential = "token:${config.age.secrets.prusa-obico-token.path}";
        ExecStart = "${lib.getExe package} --token-file %d/token";
        # The bridge only pets the watchdog while its supervisor loop runs, so
        # a wedged runtime gets restarted instead of silently stopping reports.
        WatchdogSec = "30s";
        Restart = "always";
        RestartSec = "10s";
        DynamicUser = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateDevices = true;
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
      };
    };

    services.nginx.virtualHosts."metrics".locations."/metrics/prusa-obico".proxyPass = "http://127.0.0.1:${toString cfg.port}/metrics";

    homelab.scrapeTargets = [
      {
        job = "prusa-obico";
        metricsPath = "/metrics/prusa-obico";
      }
    ];

    # A lost link leaves a print unwatched even while the bridge runs, so both
    # links alert, not just the service itself. The printer is off between
    # prints, so its link alerts only when it drops during a print.
    homelab.alerts.prusa-obico = [
      {
        alert = "PrusaObicoDown";
        expr = ''up{job="prusa-obico"} == 0'';
        labels = {
          severity = "critical";
          host = config.homelab.host.hostName;
          type = "service";
          oneshot = "true";
        };
        annotations.summary = "Prusa Obico bridge is down";
      }
      {
        alert = "PrusaObicoPrinterUnreachable";
        # The bridge resets the print state when the link drops, so the window
        # looks back at the state before the drop. The alert clears once the
        # window no longer covers the print.
        expr = ''prusa_obico_printer_connected == 0 and max_over_time(prusa_obico_printing[15m]) == 1'';
        for = "5m";
        labels = {
          severity = "warning";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "Prusa Obico bridge lost the printer serial link";
      }
      {
        alert = "PrusaObicoCloudUnreachable";
        expr = ''prusa_obico_obico_connected == 0'';
        for = "5m";
        labels = {
          severity = "warning";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "Prusa Obico bridge lost its Obico connection";
      }
    ];

    homelab.healthChecks = [
      {
        name = "Prusa Obico";
        script = pkgs.writeShellApplication {
          name = "health-check-prusa-obico";
          runtimeInputs = [pkgs.curl pkgs.jq];
          # The printer link is left out because the printer is off between
          # prints, and the alert above covers it during a print.
          text = ''
            curl -sf --max-time 5 http://127.0.0.1:${toString cfg.port}/status \
              | jq -e '.obico.connected' >/dev/null
          '';
        };
        timeout = 10;
      }
    ];
  };
}
