# Waybar top bar with workspaces, system monitors, and menus
#
# - floating island bar with compositor blur
# - rofi-based popup menus for network, bluetooth, audio, battery, power
# - DND toggle, theme toggle, Netbird VPN management
# - desktop entries for rofi submenu access
{
  pkgs,
  lib,
  config,
  ...
}: let
  colorsDark = config.colorScheme.darkPalette;
  colorsLight = config.colorScheme.lightPalette;
  xdgConfig = config.xdg.configHome;

  # Generate Waybar color definitions as @define-color statements.
  mkWaybarTheme = p: ''
    @define-color accent #${p.base0D};
    @define-color panelBg #${p.panelBg};
    @define-color base00 #${p.base00};
    @define-color base01 #${p.base01};
    @define-color base02 #${p.base02};
    @define-color base03 #${p.base03};
    @define-color base04 #${p.base04};
    @define-color base05 #${p.base05};
    @define-color base06 #${p.base06};
    @define-color base07 #${p.base07};
    @define-color base08 #${p.base08};
    @define-color base09 #${p.base09};
    @define-color base0A #${p.base0A};
    @define-color base0B #${p.base0B};
    @define-color base0C #${p.base0C};
    @define-color base0D #${p.base0D};
    @define-color base0E #${p.base0E};
    @define-color base0F #${p.base0F};
  '';

  # Static Waybar layout CSS that imports mutable colors.css for theme values.
  waybarLayoutCss = ''
    @import url("colors.css");

    * {
      font-family: "DejaVuSansM Nerd Font", sans-serif;
      font-size: 18px;
      min-height: 0;
    }

    window#waybar {
      background: transparent;
      color: @base03;
    }

    /* Floating island bar with darker chrome background. Matches upstream
       Tokyo Night where sidebar and statusbar are darker than the editor. */
    window#waybar > box {
      background: @panelBg;
      border-radius: 8px;
      border: 1px solid alpha(@accent, 0.2);
      margin: 4px 8px 0 8px;
    }

    /* Workspace indicators recessed into the bar surface. */
    #workspaces {
      background: @base00;
      border-radius: 6px;
      margin: 4px 4px;
      padding: 0 4px;
    }

    #workspaces button {
      padding: 4px 8px;
      margin: 4px 2px;
      color: @base03;
      background: transparent;
      border-radius: 6px;
      font-size: 14px;
      transition: background 200ms ease;
    }

    #workspaces button.active {
      color: @base00;
      background: @accent;
    }

    #workspaces button:hover {
      color: @base05;
      background: @base02;
    }

    #window {
      color: @base03;
      margin-left: 12px;
    }

    /* Center: clock and media player. */
    #clock {
      color: @base05;
      font-weight: bold;
      padding: 4px 16px;
    }

    #mpris {
      color: @base03;
      font-style: italic;
      font-size: 14px;
      padding: 4px 12px;
    }

    /* Right-side modules in a grouped pill. */
    #temperature,
    #cpu,
    #memory,
    #battery {
      padding: 4px 6px;
      margin: 4px 0;
      min-width: 60px;
      transition: background 200ms ease;
      border-radius: 6px;
      /* Use a monospace font feature for fixed-width digits. GTK CSS does not
         support font-variant-numeric, so font-feature-settings is the fallback. */
      font-feature-settings: "tnum";
    }

    /* Icon-only modules without min-width to avoid wasted space. */
    #custom-network,
    #bluetooth,
    #pulseaudio,
    #language {
      padding: 4px 8px;
      margin: 4px 2px;
      border-radius: 6px;
      transition: background 200ms ease;
    }

    tooltip {
      background: @panelBg;
      border: 1px solid @base01;
      border-radius: 4px;
      color: @base05;
    }

    /* GTK tooltip labels do not reliably inherit the parent color. */
    tooltip label {
      color: @base05;
    }

    #temperature:hover,
    #cpu:hover,
    #memory:hover,
    #custom-network:hover,
    #bluetooth:hover,
    #pulseaudio:hover,
    #language:hover,
    #battery:hover {
      background: @base02;
    }

    #privacy {
      padding: 4px 6px;
      margin: 4px 2px;
    }

    /* Visual gap between metrics group and controls group. */
    #custom-dnd {
      padding: 4px 8px;
      margin: 4px 2px 4px 12px;
      border-radius: 6px;
      transition: background 200ms ease;
    }

    #custom-dnd:hover {
      background: @base02;
    }

    #custom-dnd.dnd {
      color: @base09;
    }

    #tray {
      color: @base03;
      padding: 4px 8px;
      margin: 4px 2px;
    }

    #battery.warning {
      color: @base0D;
    }

    #battery.critical {
      color: @base08;
    }

    #custom-darkmode {
      padding: 4px 8px;
      margin: 4px 2px;
      border-radius: 6px;
      transition: background 200ms ease;
    }

    #custom-darkmode:hover {
      background: @base02;
    }

    #custom-power {
      color: @accent;
      padding: 4px 12px;
      margin: 4px 4px 4px 0;
      border-radius: 6px;
      transition: background 200ms ease;
    }

    #custom-power:hover {
      background: @base02;
    }
  '';

  powerMenu = pkgs.writeShellApplication {
    name = "waybar-power-menu";
    runtimeInputs = with pkgs; [rofi systemd hyprland];
    text = ''
      log() { echo "$*" | systemd-cat -t waybar-power-menu -p info; }

      choice=$(printf "  Lock\n  Suspend\n  Reboot\n  Shutdown\n󰍃  Log Out" \
        | rofi -dmenu -p "Power" -theme-str 'listview { lines: 5; }') || exit 0
      log "selected: $choice"
      case "$choice" in
        *Lock) loginctl lock-session ;;
        *Suspend) systemctl suspend ;;
        *Reboot) systemctl reboot ;;
        *Shutdown) systemctl poweroff ;;
        *"Log Out") hyprctl dispatch exit ;;
      esac
    '';
  };

  # Waybar network status script. Combines network and VPN state into a single
  # JSON output with icon, tooltip, and CSS class.
  networkStatus = pkgs.writeShellApplication {
    name = "waybar-network-status";
    runtimeInputs = with pkgs; [jq networkmanager systemd coreutils];
    text = ''
      log() { echo "$*" | systemd-cat -t waybar-network-status -p info; }

      # Determine primary connection type and name
      primary=$(nmcli -t -f TYPE,STATE,CONNECTION device status 2>/dev/null \
        | grep ":connected:" | head -1 || true)
      type=$(echo "$primary" | cut -d: -f1)
      conn=$(echo "$primary" | cut -d: -f3)

      case "$type" in
        wifi)
          signal=$(nmcli -t -f IN-USE,SIGNAL dev wifi list --rescan no 2>/dev/null \
            | grep '^\*:' | cut -d: -f2 || true)
          icon="󰤨"
          class="wifi"
          net_info="WiFi: $conn (''${signal:-?}%)"
          ;;
        ethernet)
          icon="󰈀"
          class="ethernet"
          net_info="Ethernet: $conn"
          ;;
        *)
          icon="󰤭"
          class="disconnected"
          net_info="Network: disconnected"
          ;;
      esac

      # Collect VPN status for the tooltip. Timeout prevents netbird from
      # blocking the script when the daemon is unresponsive.
      vpn_info=""
      nb_status=$(timeout 3 netbird-user status 2>/dev/null | head -1 || true)
      if echo "$nb_status" | grep -qi "connected"; then
        vpn_info="Netbird: connected"
      fi
      nm_vpn=$(nmcli -t -f NAME,TYPE,DEVICE connection show --active 2>/dev/null \
        | grep ':vpn:' | cut -d: -f1 | head -1 || true)
      if [ -n "$nm_vpn" ]; then
        vpn_info="''${vpn_info:+$vpn_info\n}VPN: $nm_vpn"
      fi

      tooltip="$net_info"
      [ -n "$vpn_info" ] && tooltip="$tooltip\n$vpn_info"

      jq -cn --arg text "$icon" --arg class "$class" --arg tooltip "$tooltip" \
        '{text: $text, class: $class, tooltip: $tooltip}'
    '';
  };

  networkMenu = pkgs.writeShellApplication {
    name = "waybar-network-menu";
    runtimeInputs = with pkgs; [networkmanager rofi networkmanagerapplet libnotify systemd gnused];
    text = ''
      log() { echo "$*" | systemd-cat -t waybar-network-menu -p info; }

      while true; do
        # Collect active connection names for marking in the list
        active_names=$(nmcli -t -f NAME connection show --active 2>/dev/null || true)

        wifi=$(nmcli radio wifi)
        toggle=$([ "$wifi" = "enabled" ] && echo "󰤭  Disable WiFi" || echo "󰤨  Enable WiFi")

        # List saved connections split by type
        wired=$(nmcli -t -f NAME,TYPE connection show | while IFS=: read -r name type; do
          [ "$type" != "802-3-ethernet" ] && continue
          is_active=$(echo "$active_names" | grep -Fxc "$name" || true)
          [ "$is_active" -ge 1 ] \
            && echo "󰈀  $name (active)" \
            || echo "󰈀  $name"
        done || true)

        wireless=$(nmcli -t -f NAME,TYPE connection show | while IFS=: read -r name type; do
          [ "$type" != "802-11-wireless" ] && continue
          is_active=$(echo "$active_names" | grep -Fxc "$name" || true)
          [ "$is_active" -ge 1 ] \
            && echo "󰤨  $name (active)" \
            || echo "󰤟  $name"
        done || true)

        # Collect NM VPN connections with status
        vpns=$(nmcli -t -f NAME,TYPE connection show | grep ':vpn$' | cut -d: -f1 | while read -r name; do
          active=$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null \
            | grep ':vpn$' | cut -d: -f1 | grep -Fxc "$name" || true)
          [ "''${active:-0}" -ge 1 ] \
            && echo "󰌾  $name (active)" \
            || echo "󰌿  $name"
        done || true)

        # Check netbird status
        nb_line=""
        nb_status=$(netbird-user status 2>/dev/null | head -1 || true)
        if echo "$nb_status" | grep -qi "connected"; then
          nb_line="󰌾  Netbird (connected)"
        elif command -v netbird-user >/dev/null 2>&1; then
          nb_line="󰌿  Netbird"
        fi

        # Build VPN section if any VPN entries exist
        vpn_section=""
        [ -n "$vpns" ] && vpn_section="$vpns"
        [ -n "$nb_line" ] && vpn_section="''${vpn_section:+$vpn_section\n}$nb_line"

        # Assemble menu with separators between wired, wifi, vpn, and settings
        entries=""
        [ -n "$wired" ] && entries="$wired"
        if [ -n "$wireless" ]; then
          [ -n "$entries" ] && entries="$entries\n───────────"
          entries="$entries\n$wireless\n$toggle"
        else
          entries="$entries\n$toggle"
        fi
        [ -n "$vpn_section" ] && entries="$entries\n───────────\n$vpn_section"
        entries="$entries\n───────────\n  Settings"

        choice=$(printf "%b" "$entries" | rofi -dmenu -p "Network") || break
        log "selected: $choice"

        case "$choice" in
          *Settings) nm-connection-editor; break ;;
          "───────────") ;;
          *"Disable WiFi") nmcli radio wifi off ;;
          *"Enable WiFi") nmcli radio wifi on ;;
          *"Netbird (connected)")
            netbird-user down \
              || { notify-send -u critical "Network" "Failed to disconnect Netbird"; continue; }
            notify-send "Network" "Netbird disconnected"
            ;;
          *"Netbird")
            netbird-user up \
              || { notify-send -u critical "Network" "Failed to connect Netbird"; continue; }
            notify-send "Network" "Netbird connected"
            ;;
          *"(active)"*)
            # Extract connection name from between icon and status marker
            name="''${choice#*  }"
            name="''${name% (active)}"
            nmcli connection down "$name" \
              || { notify-send -u critical "Network" "Failed to disconnect from $name"; continue; }
            notify-send "Network" "Disconnected from $name"
            ;;
          "󰤟  "*)
            name="''${choice#󰤟  }"
            nmcli connection up "$name" \
              || { notify-send -u critical "Network" "Failed to connect to $name"; continue; }
            notify-send "Network" "Connected to $name"
            ;;
          "󰈀  "*)
            name="''${choice#󰈀  }"
            nmcli connection up "$name" \
              || { notify-send -u critical "Network" "Failed to connect to $name"; continue; }
            notify-send "Network" "Connected to $name"
            ;;
          "󰌿  "*)
            name="''${choice#󰌿  }"
            nmcli connection up "$name" \
              || { notify-send -u critical "Network" "Failed to connect to $name"; continue; }
            notify-send "Network" "Connected to $name"
            ;;
        esac
      done
    '';
  };

  audioMenu = pkgs.writeShellApplication {
    name = "waybar-audio-menu";
    runtimeInputs = with pkgs; [wireplumber rofi pavucontrol gawk systemd];
    text = ''
      log() { echo "$*" | systemd-cat -t waybar-audio-menu -p info; }

      while true; do
        vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf "%.0f", $2 * 100}')
        muted=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -c MUTED || true)
        status=$([ "$muted" -eq 1 ] && echo "muted" || echo "''${vol}%")

        choice=$(printf "󰕾  Volume: %s\n󰝟  Toggle mute\n󰝝  Volume up\n󰝞  Volume down\n───────────\n  Settings" "$status" \
          | rofi -dmenu -p "Audio" -theme-str 'listview { lines: 6; }') || break
        log "selected: $choice"

        case "$choice" in
          "───────────") ;;
          *Settings) pavucontrol; break ;;
          *"Toggle mute"*) wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
          *"Volume up"*) wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+ ;;
          *"Volume down"*) wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
        esac
      done
    '';
  };

  batteryMenu = pkgs.writeShellApplication {
    name = "waybar-battery-menu";
    runtimeInputs = with pkgs; [power-profiles-daemon rofi systemd];
    text = ''
      log() { echo "$*" | systemd-cat -t waybar-battery-menu -p info; }

      while true; do
        capacity=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo "?")
        bat_status=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "Unknown")
        profile=$(powerprofilesctl get 2>/dev/null || echo "unknown")

        # Mark the active profile
        perf=$([ "$profile" = "performance" ] && echo "󰓅  Performance (active)" || echo "󰓅  Performance")
        balanced=$([ "$profile" = "balanced" ] && echo "󰗑  Balanced (active)" || echo "󰗑  Balanced")
        saver=$([ "$profile" = "power-saver" ] && echo "󰌪  Power Saver (active)" || echo "󰌪  Power Saver")

        choice=$(printf "󰁹  Battery: %s%% (%s)\n───────────\n%s\n%s\n%s" \
          "$capacity" "$bat_status" "$perf" "$balanced" "$saver" \
          | rofi -dmenu -p "Battery" -theme-str 'listview { lines: 5; }') || break
        log "selected: $choice"

        case "$choice" in
          "───────────") ;;
          *Performance*) powerprofilesctl set performance ;;
          *Balanced*) powerprofilesctl set balanced ;;
          *"Power Saver"*) powerprofilesctl set power-saver ;;
        esac
      done
    '';
  };

  bluetoothMenu = pkgs.writeShellApplication {
    name = "waybar-bluetooth-menu";
    runtimeInputs = with pkgs; [bluez rofi blueman gawk gnused systemd];
    text = ''
      log() { echo "$*" | systemd-cat -t waybar-bluetooth-menu -p info; }

      while true; do
        powered=$(bluetoothctl show 2>/dev/null | grep -c "Powered: yes" || true)
        toggle=$([ "$powered" -ge 1 ] && echo "󰂲  Disable Bluetooth" || echo "󰂯  Enable Bluetooth")

        # List paired devices with connection status
        devices=$(bluetoothctl devices Paired 2>/dev/null | while read -r _ mac name; do
          connected=$(bluetoothctl info "$mac" 2>/dev/null | grep -c "Connected: yes" || true)
          [ "$connected" -ge 1 ] \
            && echo "󰂱  $name (connected)" \
            || echo "󰂯  $name"
        done || true)

        choice=$(printf "%s\n%s\n───────────\n  Settings" "$devices" "$toggle" \
          | rofi -dmenu -p "Bluetooth") || break
        log "selected: $choice"

        case "$choice" in
          "───────────") ;;
          *Settings) blueman-manager; break ;;
          *"Disable Bluetooth"*) bluetoothctl power off ;;
          *"Enable Bluetooth"*) bluetoothctl power on ;;
          *"(connected)"*)
            name="''${choice#󰂱  }"
            name="''${name% (connected)}"
            mac=$(bluetoothctl devices Paired | grep " $name$" | awk '{print $2}')
            bluetoothctl disconnect "$mac"
            ;;
          "󰂯  "*)
            name="''${choice#󰂯  }"
            mac=$(bluetoothctl devices Paired | grep " $name$" | awk '{print $2}')
            bluetoothctl connect "$mac"
            ;;
        esac
      done
    '';
  };

  # Toggle Do Not Disturb mode via mako and signal waybar to update the icon.
  dndToggle = pkgs.writeShellApplication {
    name = "waybar-dnd-toggle";
    runtimeInputs = with pkgs; [mako procps systemd];
    text = ''
      log() { echo "$*" | systemd-cat -t waybar-dnd-toggle -p info; }

      current=$(makoctl mode)
      if echo "$current" | grep -q "do-not-disturb"; then
        makoctl mode -s default
        log "DND disabled"
      else
        makoctl mode -s do-not-disturb
        log "DND enabled"
      fi
      pkill -SIGRTMIN+9 waybar || true
    '';
  };

  dndStatus = pkgs.writeShellApplication {
    name = "waybar-dnd-status";
    runtimeInputs = with pkgs; [mako systemd];
    text = ''
      current=$(makoctl mode 2>/dev/null || echo "default")
      if echo "$current" | grep -q "do-not-disturb"; then
        printf '{"text": "󰂛", "class": "dnd", "tooltip": "Notifications: paused"}\n'
      else
        printf '{"text": "󰂚", "class": "normal", "tooltip": "Notifications: on"}\n'
      fi
    '';
  };

  darkmodeStatus = pkgs.writeShellApplication {
    name = "waybar-darkmode-status";
    text = ''
      mode=$(cat "${xdgConfig}/theme-mode" 2>/dev/null || echo dark)
      if [ "$mode" = "light" ]; then
        echo "󰖨"
      else
        echo "󰖔"
      fi
    '';
  };

  # Netbird VPN management menu with rofi interface. Shows connection state,
  # peers, and routes from the netbird-user CLI.
  netbirdMenu = pkgs.writeShellApplication {
    name = "waybar-netbird-menu";
    runtimeInputs = with pkgs; [rofi jq libnotify alacritty systemd];
    text = ''
      log() { echo "$*" | systemd-cat -t waybar-netbird-menu -p info; }

      while true; do
        # Determine connection state
        nb_json=$(netbird-user status --json 2>/dev/null || echo '{}')
        mgmt_connected=$(echo "$nb_json" | jq -r '.management.connected // false')

        if [ "$mgmt_connected" = "true" ]; then
          status_line="󰌾  Netbird: Connected"
          toggle_line="󰌿  Disconnect"
        else
          status_line="󰌿  Netbird: Disconnected"
          toggle_line="󰌾  Connect"
        fi

        # Build peers list from JSON
        peers=$(echo "$nb_json" | jq -r '
          .peers.details // [] | .[] |
          "    " + .fqdn + " (" + .netbirdIp + ") " +
          if .connected then "✓" else "✗" end
        ' 2>/dev/null || true)

        # Build routes list
        routes=$(netbird-user routes list 2>/dev/null | while read -r line; do
          echo "    $line"
        done || true)

        # Assemble menu
        entries="$status_line"
        entries="$entries\n───────────"
        entries="$entries\n$toggle_line"

        if [ -n "$peers" ]; then
          entries="$entries\n───────────"
          entries="$entries\n  Peers:"
          entries="$entries\n$peers"
        fi

        if [ -n "$routes" ]; then
          entries="$entries\n───────────"
          entries="$entries\n  Routes:"
          entries="$entries\n$routes"
        fi

        entries="$entries\n───────────"
        entries="$entries\n  Status Details"

        choice=$(printf "%b" "$entries" | rofi -dmenu -p "Netbird" \
          -theme-str 'listview { lines: 15; }' \
          -theme-str 'window { width: 700px; }') || break
        log "selected: $choice"

        case "$choice" in
          "───────────") ;;
          *Disconnect*)
            netbird-user down \
              || { notify-send -u critical "Netbird" "Failed to disconnect"; continue; }
            notify-send "Netbird" "Disconnected"
            ;;
          *Connect*)
            netbird-user up \
              || { notify-send -u critical "Netbird" "Failed to connect"; continue; }
            notify-send "Netbird" "Connected"
            ;;
          *"Status Details"*)
            alacritty -e bash -c 'netbird-user status --detail; echo "Press Enter to close"; read -r'
            break
            ;;
        esac
      done
    '';
  };
in {
  # Nix-managed waybar color variant files for the theme toggle.
  xdg.configFile."waybar/${config.colorScheme.themeName}-dark.css".text = mkWaybarTheme colorsDark;
  xdg.configFile."waybar/${config.colorScheme.themeName}-light.css".text = mkWaybarTheme colorsLight;

  # Full-width translucent bar with compositor blur.
  # [workspace dots | window]  [clock  mpris]  [privacy dnd tray cpu mem net+vpn bt vol lang bat power]
  programs.waybar = {
    enable = true;
    systemd = {
      enable = true;
      target = "hyprland-session.target";
    };
    settings = [
      {
        layer = "top";
        position = "top";
        spacing = 4;
        reload_style_on_change = true;
        modules-left = ["hyprland/workspaces" "hyprland/window"];
        modules-center = ["clock" "mpris"];
        modules-right = ["privacy" "tray" "temperature" "cpu" "memory" "custom/dnd" "hyprland/language" "custom/network" "bluetooth" "pulseaudio" "battery" "custom/darkmode" "custom/power"];

        "hyprland/workspaces" = {
          # {icon} shows workspace state from format-icons, {windows} shows
          # per-window app icons from window-rewrite. Combined so empty
          # workspaces get ○ and occupied ones show app icons.
          format = "{icon}{windows}";
          format-icons = {
            empty = "○";
            default = "";
          };
          format-window-separator = " ";
          window-rewrite-default = "●";
          window-rewrite = {
            "class<Alacritty>" = "󰆍";
            "class<firefox>" = "󰈹";
            "class<zen|app.zen_browser.zen>" = "󰈹";
            "class<org.gnome.Nautilus>" = "󰝰";
            "class<kicad>" = "󰻫";
            "class<FreeCAD>" = "󰻫";
          };
          on-click = "activate";
          on-scroll-up = "hyprctl dispatch workspace e-1";
          on-scroll-down = "hyprctl dispatch workspace e+1";
          persistent-workspaces."*" = 3;
        };
        "hyprland/window" = {
          format = "{}";
          max-length = 40;
          rewrite = {
            # Strip trailing " - App Name" suffixes for cleaner display.
            "(.*) — Mozilla Firefox" = "󰈹 $1";
            "(.*) - Alacritty" = "󰆍 $1";
            "(.*) – Nautilus" = "󰝰 $1";
          };
        };
        clock = {
          format = "{:%a %b %d  %H:%M}";
          tooltip-format = "<tt>{calendar}</tt>";
          calendar = {
            format = {
              today = "<b><u>{}</u></b>";
            };
          };
        };
        mpris = {
          format = "{player_icon} {title} - {artist}";
          format-paused = "{player_icon} {status_icon} {title} - {artist}";
          player-icons = {
            default = "▶";
            firefox = "󰈹";
            spotify = "󰓇";
          };
          status-icons = {
            paused = "󰏤";
          };
          title-len = 30;
          artist-len = 20;
        };
        privacy = {
          icon-size = 18;
          icon-spacing = 4;
        };
        "custom/dnd" = {
          exec = lib.getExe dndStatus;
          return-type = "json";
          interval = "once";
          signal = 9;
          on-click = lib.getExe dndToggle;
        };
        temperature = {
          format = "{icon}{temperatureC:3}°";
          format-icons = ["󱃃" "󰔏" "󱃂"];
          critical-threshold = 80;
          interval = 10;
          on-click = "alacritty -e btop";
        };
        cpu = {
          format = "󰍛{usage:3}%";
          interval = 10;
          on-click = "alacritty -e btop";
        };
        memory = {
          format = "󰘚{percentage:3}%";
          interval = 10;
          on-click = "alacritty -e btop";
        };
        "custom/network" = {
          exec = lib.getExe networkStatus;
          return-type = "json";
          interval = 10;
          on-click = lib.getExe networkMenu;
        };
        bluetooth = {
          format = "󰂯";
          format-connected = "󰂱";
          format-disabled = "󰂲";
          tooltip-format-connected = "{device_alias}";
          on-click = lib.getExe bluetoothMenu;
        };
        pulseaudio = {
          format = "{icon}";
          format-muted = "󰖁";
          format-icons = {
            default = ["󰕿" "󰖀" "󰕾"];
          };
          on-click = lib.getExe audioMenu;
        };
        "hyprland/language" = {
          format = "{short}";
          on-click = "hyprctl switchxkblayout all next";
        };
        battery = {
          format = "{icon} {capacity}%";
          format-charging = "󰂄 {capacity}%";
          format-icons = ["󰂎" "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹"];
          states = {
            warning = 20;
            critical = 10;
          };
          on-click = lib.getExe batteryMenu;
        };
        tray = {
          spacing = 8;
        };
        "custom/darkmode" = {
          format = "{}";
          exec = lib.getExe darkmodeStatus;
          on-click = lib.getExe config.hyprland.toggleTheme;
          interval = "once";
          signal = 8;
          tooltip-format = "Toggle theme: dark / light";
        };
        "custom/power" = {
          format = "⏻";
          on-click = lib.getExe powerMenu;
          tooltip = false;
        };
      }
    ];
    style = waybarLayoutCss;
  };

  # Waybar crashes if it starts before Hyprland accepts Wayland clients.
  # Default systemd restart limits give up too quickly, so allow retries
  # over a longer window until the compositor is ready.
  systemd.user.services.waybar = {
    Unit = {
      StartLimitIntervalSec = 30;
      StartLimitBurst = 10;
    };
    Service.RestartSec = 2;
  };

  # Desktop entries for rofi submenu access. Typing "wifi", "bluetooth", etc.
  # in the main rofi drun launcher opens the corresponding menu.
  xdg.desktopEntries = {
    wifi-settings = {
      name = "WiFi & Network";
      exec = lib.getExe networkMenu;
      icon = "network-wireless";
      comment = "Manage WiFi, VPN, and network connections";
      categories = ["Settings" "Network"];
      terminal = false;
      settings.Keywords = "wifi;network;vpn;netbird;ethernet;connection;";
    };
    bluetooth-settings = {
      name = "Bluetooth";
      exec = lib.getExe bluetoothMenu;
      icon = "bluetooth";
      comment = "Manage Bluetooth devices";
      categories = ["Settings"];
      terminal = false;
      settings.Keywords = "bluetooth;pair;headphones;speaker;";
    };
    battery-power = {
      name = "Battery & Power";
      exec = lib.getExe batteryMenu;
      icon = "battery";
      comment = "Battery status and power profiles";
      categories = ["Settings"];
      terminal = false;
      settings.Keywords = "battery;power;profile;performance;balanced;saver;";
    };
    audio-volume = {
      name = "Audio & Volume";
      exec = lib.getExe audioMenu;
      icon = "audio-volume-high";
      comment = "Volume controls and audio settings";
      categories = ["Settings"];
      terminal = false;
      settings.Keywords = "audio;volume;sound;mute;speaker;";
    };
    power-menu = {
      name = "Power Menu";
      exec = lib.getExe powerMenu;
      icon = "system-shutdown";
      comment = "Lock, suspend, reboot, shutdown";
      categories = ["System"];
      terminal = false;
      settings.Keywords = "power;shutdown;reboot;suspend;lock;logout;";
    };
    theme-toggle = {
      name = "Toggle Dark/Light Mode";
      exec = lib.getExe config.hyprland.toggleTheme;
      icon = "weather-clear-night";
      comment = "Switch between dark and light theme";
      categories = ["Settings"];
      terminal = false;
      settings.Keywords = "theme;dark;light;night;day;toggle;mode;";
    };
    netbird-vpn = {
      name = "Netbird VPN";
      exec = lib.getExe netbirdMenu;
      icon = "network-vpn";
      comment = "Netbird VPN peers, routes, and connection management";
      categories = ["Network" "Settings"];
      terminal = false;
      settings.Keywords = "netbird;vpn;peers;routes;wireguard;";
    };
  };

  theme.toggle = [
    {
      name = "waybar";
      switch = pkgs.writeShellApplication {
        name = "theme-switch-waybar";
        text = ''
          cat "${xdgConfig}/waybar/${config.colorScheme.themeName}-$1.css" > "${xdgConfig}/waybar/colors.css"
        '';
      };
      seed = [
        {
          source = "${xdgConfig}/waybar/${config.colorScheme.themeName}-\${mode}.css";
          target = "${xdgConfig}/waybar/colors.css";
        }
      ];
    }
  ];
}
