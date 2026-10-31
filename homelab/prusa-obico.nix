# Prusa printer bridge to Obico
#
# - drives the printer through the serial bridge on the printer host
# - reports status and temperatures to Obico and takes pause, resume and cancel
# - uploads snapshots cut from the printer host's H.264 stream for AI detection
# - /status JSON and /metrics on localhost for debugging and prometheus
# - Janus WebRTC gateway serving Obico's real-time stream through its TURN relay
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

  # The layout mirrors the Janus config the official Obico agents generate in
  # moonraker-obico's janus_config_builder.py, so Obico's web client finds the
  # same mountpoint and media it expects from them.
  janusTransportConfig = pkgs.writeText "janus.transport.websockets.jcfg" ''
    general: {
      ws = true
      ws_port = ${toString cfg.port.janus}
      ws_ip = "127.0.0.1"
      wss = false
    }
  '';

  # The camera encodes H.264 High profile level 4.0, so the fmtp advertises
  # that instead of the constrained baseline the official agents use.
  janusStreamingConfig = pkgs.writeText "janus.plugin.streaming.jcfg" ''
    h264-1: {
      type = "rtp"
      id = 1
      description = "h264-video"
      audio = false
      video = true
      videoport = ${toString cfg.port.rtp}
      videoiface = "127.0.0.1"
      videopt = 96
      videortpmap = "H264/90000"
      videofmtp = "profile-level-id=640028;packetization-mode=1"
      videobufferkf = true
    }
  '';

  # The TURN credentials are the printer token, so the main config is written
  # at start from the credential instead of landing in the world-readable store.
  janusConfigScript = pkgs.writeShellScript "janus-obico-config" ''
    set -eu
    dir="$RUNTIME_DIRECTORY"
    token=$(tr -d '[:space:]' < "$CREDENTIALS_DIRECTORY/token")
    cp ${janusTransportConfig} "$dir/janus.transport.websockets.jcfg"
    cp ${janusStreamingConfig} "$dir/janus.plugin.streaming.jcfg"
    cat > "$dir/janus.jcfg" <<EOF
    general: {
      configs_folder = "$dir"
      plugins_folder = "${pkgs.janus-gateway}/lib/janus/plugins"
      transports_folder = "${pkgs.janus-gateway}/lib/janus/transports"
      events_folder = "${pkgs.janus-gateway}/lib/janus/events"
      loggers_folder = "${pkgs.janus-gateway}/lib/janus/loggers"
    }
    plugins: {
      disable = "libjanus_audiobridge.so,libjanus_echotest.so,libjanus_nosip.so,libjanus_recordplay.so,libjanus_sip.so,libjanus_textroom.so,libjanus_videocall.so,libjanus_videoroom.so"
    }
    transports: {
      disable = "libjanus_http.so,libjanus_pfunix.so"
    }
    loggers: {
      disable = "libjanus_jsonlog.so"
    }
    events: {
      disable = "libjanus_gelfevh.so,libjanus_sampleevh.so,libjanus_wsevh.so"
    }
    nat: {
      turn_server = "turn.obico.io"
      turn_port = 80
      turn_type = "tcp"
      turn_user = "$token"
      turn_pwd = "$token"
      ice_ignore_list = "vmnet"
      ignore_unreachable_ice_server = true
    }
    EOF
  '';
in {
  options.homelab.prusa-obico = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the Prusa printer bridge to Obico";
    };

    port = {
      http = lib.mkOption {
        type = lib.types.port;
        default = 9188;
        description = "Port for the /status and /metrics endpoints";
      };

      janus = lib.mkOption {
        type = lib.types.port;
        default = 17730;
        description = "Port of the Janus websocket API at localhost";
      };

      rtp = lib.mkOption {
        type = lib.types.port;
        default = 17732;
        description = "Port the Janus mountpoint receives the H.264 RTP feed on";
      };
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
        PRUSA_OBICO_LISTEN = "127.0.0.1:${toString cfg.port.http}";
        PRUSA_OBICO_JANUS_WS = "ws://127.0.0.1:${toString cfg.port.janus}/";
        PRUSA_OBICO_RTP_PORT = toString cfg.port.rtp;
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

    # Media leaves through Obico's TURN relay, which Janus reaches outbound,
    # so no port opens on the firewall.
    systemd.services.janus-obico = {
      description = "Janus WebRTC gateway for the Obico live stream";
      wants = ["network-online.target"];
      after = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        LoadCredential = "token:${config.age.secrets.prusa-obico-token.path}";
        RuntimeDirectory = "janus-obico";
        RuntimeDirectoryMode = "0700";
        ExecStartPre = janusConfigScript;
        ExecStart = "${pkgs.janus-gateway}/bin/janus --config=%t/janus-obico/janus.jcfg --configs-folder=%t/janus-obico --stun-server=stun.l.google.com:19302 --disable-colors";
        Restart = "always";
        RestartSec = "10s";
        DynamicUser = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateDevices = true;
        # libnice enumerates the host interfaces over netlink for ICE.
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK"];
      };
    };

    services.nginx.virtualHosts."metrics".locations."/metrics/prusa-obico".proxyPass = "http://127.0.0.1:${toString cfg.port.http}/metrics";

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
        alert = "PrusaObicoJanusDown";
        expr = ''node_systemd_unit_state{name="janus-obico.service",state="active",host="${config.homelab.host.hostName}"} == 0'';
        for = "5m";
        labels = {
          severity = "warning";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "Janus gateway for the Obico live stream is not active";
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
            curl -sf --max-time 5 http://127.0.0.1:${toString cfg.port.http}/status \
              | jq -e '.obico.connected' >/dev/null
          '';
        };
        timeout = 10;
      }
    ];
  };
}
