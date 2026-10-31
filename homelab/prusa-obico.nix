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

  # Ports come from the printer host so the two sides cannot drift apart.
  printerConfig = inputs.self.nixosConfigurations.${cfg.printerHost}.config.homelab;

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

  # The camera is set to encode Constrained Baseline level 3.1 in webcam.nix, so
  # the fmtp advertises the same, as the official Obico agents do. Every WebRTC
  # browser must support it, while a browser that cannot take the advertised
  # profile rejects the only video m-line and the stream never starts.
  #
  # Janus ignores the old videobufferkf flag since it deprecated it. A new
  # viewer would wait for the next keyframe, up to a second away, so the
  # mountpoint keeps the latest keyframe and the deltas of the 100 ms behind it.
  # The burst stays small and the keyframe arrives within a few packets.
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
      videofmtp = "profile-level-id=42e01f;packetization-mode=1"
      bufferkf_ms = 100
    }
  '';

  # Janus loads every module it finds in these folders, and the disable lists
  # of its config name modules one by one, so a module added by a package
  # update would load unnoticed. These folders hold only what the stream
  # needs, which keeps the unused plugins and transports out of the process.
  janusLib = "${pkgs.janus-gateway}/lib/janus";
  janusPlugins = pkgs.linkFarm "janus-obico-plugins" [
    {
      name = "libjanus_streaming.so";
      path = "${janusLib}/plugins/libjanus_streaming.so";
    }
  ];
  janusTransports = pkgs.linkFarm "janus-obico-transports" [
    {
      name = "libjanus_websockets.so";
      path = "${janusLib}/transports/libjanus_websockets.so";
    }
  ];
  # The stream needs no event handlers or loggers, so their folders are empty.
  janusEmptyFolder = pkgs.linkFarm "janus-obico-empty" [];

  # The TURN credentials are the printer token, so the main config is written
  # at start from the credential instead of landing in the world-readable store.
  janusConfigScript = pkgs.writeShellApplication {
    name = "janus-obico-config";
    runtimeInputs = [pkgs.coreutils pkgs.gnused];
    text = ''
      dir="$RUNTIME_DIRECTORY"
      # The token lands inside libconfig string literals, so a backslash or
      # quote in it is escaped instead of ending the string early.
      token=$(tr -d '[:space:]' < "$CREDENTIALS_DIRECTORY/token" | sed 's/[\\"]/\\&/g')
      ln -s ${janusTransportConfig} "$dir/janus.transport.websockets.jcfg"
      ln -s ${janusStreamingConfig} "$dir/janus.plugin.streaming.jcfg"
      cat > "$dir/janus.jcfg" <<EOF
      general: {
        plugins_folder = "${janusPlugins}"
        transports_folder = "${janusTransports}"
        events_folder = "${janusEmptyFolder}"
        loggers_folder = "${janusEmptyFolder}"
      }
      nat: {
        stun_server = "stun.l.google.com"
        stun_port = 19302
        turn_server = "turn.obico.io"
        turn_port = 80
        turn_type = "tcp"
        turn_user = "$token"
        turn_pwd = "$token"
        ice_ignore_list = "vmnet"
      }
      EOF
    '';
  };
in {
  options.homelab.prusa-obico = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the Prusa printer bridge to Obico";
    };

    package = lib.mkPackageOption pkgs "prusa-obico" {};

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
      type = lib.types.enum (lib.attrNames config.homelab.hosts);
      description = "Host running the serial bridge and webcam for the printer";
    };
  };

  config = lib.mkIf cfg.enable {
    # The bridge reads its ports and URLs from the printer host, and those
    # options keep their defaults even when the services there are off, so
    # only an assertion catches a printer host that serves nothing.
    assertions = [
      {
        assertion = printerConfig.serial-bridge.enable && printerConfig.webcam.enable;
        message = "homelab.prusa-obico requires homelab.serial-bridge.enable and homelab.webcam.enable on ${cfg.printerHost}";
      }
    ];

    age.secrets.prusa-obico-token.rekeyFile = ../secrets/prusa-obico-token.age;

    systemd.services.prusa-obico = {
      description = "Prusa printer bridge to Obico";
      wants = ["network-online.target"];
      after = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      environment = {
        PRUSA_OBICO_PRINTER = "${printerConfig.host.peerName}:${toString printerConfig.serial-bridge.port.proxy}";
        PRUSA_OBICO_VIDEO_URL = printerConfig.webcam.url.video;
        PRUSA_OBICO_LISTEN = "127.0.0.1:${toString cfg.port.http}";
        PRUSA_OBICO_JANUS_WS = "ws://127.0.0.1:${toString cfg.port.janus}/";
        PRUSA_OBICO_RTP_PORT = toString cfg.port.rtp;
      };
      serviceConfig = {
        Type = "notify";
        # The token file is passed as a credential, which systemd reads as
        # root, so the dynamic user needs no access to the agenix secret.
        LoadCredential = "token:${config.age.secrets.prusa-obico-token.path}";
        ExecStart = "${lib.getExe cfg.package} --token-file %d/token";
        # The bridge only pets the watchdog while its main loop runs, so
        # a wedged runtime gets restarted instead of silently stopping reports.
        WatchdogSec = "30s";
        Restart = "always";
        RestartSec = "10s";
        DynamicUser = true;
        # On older firmware M27 cannot tell a paused print from an idle printer,
        # so the bridge keeps its pause flag here to survive a restart during a
        # pause.
        StateDirectory = "prusa-obico";
        ProtectHome = true;
        PrivateDevices = true;
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
      };
    };

    # Media leaves through Obico's TURN relay, which Janus reaches outbound,
    # so no port opens on the firewall. Janus resolves its STUN and TURN servers
    # only at start, and without ignore_unreachable_ice_server a failed lookup
    # exits it, so Restart retries after an outage instead of leaving a running
    # gateway with a dead stream. A STUN outage then also blocks the start.
    systemd.services.janus-obico = {
      description = "Janus WebRTC gateway for the Obico live stream";
      wants = ["network-online.target"];
      after = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        LoadCredential = "token:${config.age.secrets.prusa-obico-token.path}";
        RuntimeDirectory = "janus-obico";
        RuntimeDirectoryMode = "0700";
        ExecStartPre = lib.getExe janusConfigScript;
        # Janus takes its configs folder only from the command line, ignoring
        # the key of that name in janus.jcfg, and finds janus.jcfg inside it.
        ExecStart = "${pkgs.janus-gateway}/bin/janus --configs-folder=%t/janus-obico --disable-colors";
        Restart = "always";
        RestartSec = "10s";
        DynamicUser = true;
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
        # Switching the printer off right after a print also drops the link, so
        # a lookback window cannot tell that from a drop mid-print. The bridge
        # latches the fact itself and clears it when the printer comes back. The
        # latch lives in memory, so a bridge restart also resolves this alert.
        expr = ''prusa_obico_link_lost_during_print == 1'';
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
      {
        alert = "PrusaObicoSnapshotsStale";
        # Obico's failure detection only sees the uploaded snapshots, so a
        # stalled camera during a print stops it without any other symptom.
        expr = ''prusa_obico_printing == 1 and time() - prusa_obico_last_snapshot_success_timestamp_seconds > 300'';
        # The timestamp reads 0 until the first upload after a bridge restart.
        for = "5m";
        labels = {
          severity = "warning";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "Prusa Obico bridge uploaded no snapshot during a print";
      }
    ];

    homelab.healthChecks = [
      {
        name = "Prusa Obico";
        script = pkgs.writeShellApplication {
          name = "health-check-prusa-obico";
          runtimeInputs = [pkgs.curl pkgs.jq];
          # The printer link is left out because the printer is off between
          # prints, and the alert above covers it during a print. Janus runs on
          # thinkcenter regardless of the printer, so a Janus link that is
          # down is always a fault.
          text = ''
            curl -sf --max-time 5 http://127.0.0.1:${toString cfg.port.http}/status \
              | jq -e '.obico.connected and .janus.connected' >/dev/null
          '';
        };
        timeout = 10;
      }
    ];
  };
}
