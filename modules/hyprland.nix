# Hyprland window manager for home-manager
#
# - waybar top bar with workspaces, system monitors, tray
# - hyprlock/hypridle for screen lock and idle management
# - mako notifications, wpaperd wallpaper, polkit agent
# - swayosd popups for volume and brightness media keys
# - tiling with rofi launcher, workspace switching
# - GNOME remains as alternative session in GDM
# - dark/light theme toggle via mutable files and nix-managed variants
{
  pkgs,
  lib,
  config,
  ...
}: let
  colorsDark = config.colorScheme.palette;
  colorsLight = config.colorScheme.lightPalette;

  # Wallpaper with centered Nix snowflake on a solid background. Renders the
  # official SVG logo in the accent color over the base bg.
  nixLogoSvg = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/NixOS/nixos-artwork/master/logo/nix-snowflake-white.svg";
    hash = "sha256-J/t94Bz0fUCL92m1JY9gznu0DLfy6uIQO6AJGK3CEAY=";
  };

  mkWallpaper = name: bg: accent:
    pkgs.runCommand "${name}.png" {
      nativeBuildInputs = [pkgs.imagemagick pkgs.librsvg];
    } ''
      rsvg-convert -w 2400 -h 2400 ${nixLogoSvg} -o logo-hires.png
      magick -size 3840x2160 xc:'#${bg}' \
        \( logo-hires.png -fill '#${accent}' -colorize 100 \
           -channel A -evaluate multiply 0.7 +channel \
           -filter Lanczos -resize 600x600 \) \
        -gravity center -composite $out
    '';

  darkWallpaper = mkWallpaper "dark-wallpaper" colorsDark.base00 colorsDark.base0D;
  lightWallpaper = mkWallpaper "light-wallpaper" colorsLight.base00 colorsLight.base0D;

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
      color: @base04;
    }

    /* Floating island bar with darker chrome background. Matches upstream
       Tokyo Night where sidebar and statusbar are darker than the editor. */
    window#waybar > box {
      background: @panelBg;
      border-radius: 8px;
      border: 1px solid alpha(@accent, 0.19);
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

    #custom-dnd {
      padding: 4px 8px;
      margin: 4px 2px;
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
      padding: 4px 8px;
      margin: 4px 2px;
    }

    #battery.warning {
      color: @accent;
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

  # Generate SwayOSD CSS from a base16 palette. Pill-shaped popup with
  # translucent background that matches the Waybar aesthetic.
  mkSwayosdTheme = p: ''
    window#osd {
      padding: 12px 20px;
      border-radius: 999px;
      border: none;
      background: alpha(#${p.base00}, 0.85);
    }

    #container {
      margin: 16px;
    }

    image, label {
      color: #${p.base05};
    }

    progressbar trough {
      min-height: 6px;
      border-radius: 999px;
      background: alpha(#${p.base02}, 0.5);
    }

    progressbar progress {
      min-height: 6px;
      border-radius: 999px;
      background: #${p.base0D};
    }
  '';

  # Generate a complete mako config for each theme variant. The toggle script
  # replaces the entire config file instead of using includes, because
  # makoctl reload does not re-read included files after their contents change.
  # Centered opaque notification panel matching rofi style. The accent parameter
  # allows dark and light modes to use different border colors.
  mkMakoTheme = p: accent: ''
    anchor=top-center
    margin=44,0,0,0
    default-timeout=5000
    width=700
    border-radius=4
    border-size=2
    padding=12
    font=DejaVuSansM Nerd Font 13
    on-button-left=invoke-default-action
    on-button-right=dismiss
    background-color=#${p.base00}
    text-color=#${p.base05}
    border-color=#${accent}

    [urgency=critical]
    border-color=#${p.base08}
  '';

  # Generate rofi color variable definitions as a rasi fragment.
  mkRofiColors = p: ''
    * {
      bg:        #${p.base00};
      fg:        #${p.base05};
      bg-alt:    #${p.base01};
      fg-muted:  #${p.base03};
      accent:    #${p.base0D};
      accent-fg: #${p.base00};
    }
  '';

  # Static rofi layout that imports mutable colors.rasi for theme values.
  rofiLayoutRasi = ''
    @import "${xdgConfig}/rofi/colors.rasi"

    * {
      background-color: var(bg);
      text-color: var(fg);
      font: "DejaVuSansM Nerd Font 16";
    }

    window {
      width: 600px;
      border: 2px solid;
      border-color: var(accent);
      border-radius: 4px;
      padding: 16px;
    }

    mainbox {
      background-color: transparent;
    }

    inputbar {
      children: [ entry ];
      padding: 8px 12px;
      margin: 0 0 8px 0;
      background-color: var(bg-alt);
      border-radius: 4px;
    }

    entry {
      placeholder: "Search...";
      placeholder-color: var(fg-muted);
      background-color: transparent;
    }

    listview {
      lines: 8;
      scrollbar: true;
      background-color: transparent;
    }

    element {
      padding: 8px 12px;
      spacing: 8px;
      border-radius: 4px;
      background-color: transparent;
    }

    element selected.normal {
      background-color: var(accent);
      text-color: var(accent-fg);
    }

    element-icon {
      size: 24px;
      background-color: transparent;
    }

    element-text {
      background-color: transparent;
      text-color: inherit;
    }
  '';

  # Generate GTK @define-color overrides for libadwaita named colors. Both
  # GTK4 and GTK3 with adw-gtk3 support these via user CSS.
  mkGtkTheme = p: ''
    @define-color accent_bg_color #${p.base0D};
    @define-color accent_fg_color #${p.base00};
    @define-color accent_color #${p.base0D};
    @define-color window_bg_color #${p.base00};
    @define-color window_fg_color #${p.base05};
    @define-color view_bg_color #${p.base00};
    @define-color view_fg_color #${p.base05};
    @define-color headerbar_bg_color #${p.panelBg};
    @define-color headerbar_fg_color #${p.base05};
    @define-color card_bg_color #${p.base01};
    @define-color card_fg_color #${p.base05};
    @define-color sidebar_bg_color #${p.panelBg};
    @define-color sidebar_fg_color #${p.base05};
    @define-color popover_bg_color #${p.base01};
    @define-color popover_fg_color #${p.base05};
    @define-color dialog_bg_color #${p.base01};
    @define-color dialog_fg_color #${p.base05};
  '';

  xdgConfig = config.xdg.configHome;

  # Toggle between dark and light mode at runtime. Each registered
  # theme.toggle entry provides its own switch script called with the mode.
  toggleTheme = pkgs.writeShellApplication {
    name = "waybar-toggle-theme";
    runtimeInputs = with pkgs; [systemd procps];
    text = ''
      log() { echo "$*" | systemd-cat -t waybar-toggle-theme -p info; }

      mode_file="${xdgConfig}/theme-mode"
      current=$(cat "$mode_file" 2>/dev/null || echo "dark")

      case "$current" in
        dark) mode="light" ;;
        *)    mode="dark" ;;
      esac

      log "switching theme from $current to $mode"

      ${lib.concatMapStringsSep "\n" (t: ''
          # ${t.name}
          ${lib.getExe t.switch} "$mode"
        '')
        config.theme.toggle}

      echo "$mode" > "$mode_file"
      pkill -SIGRTMIN+8 waybar || true
    '';
  };

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
    runtimeInputs = with pkgs; [networkmanager systemd];
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

      # Collect VPN status for the tooltip
      vpn_info=""
      nb_status=$(netbird-user status 2>/dev/null | head -1 || true)
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

      printf '{"text": "%s", "class": "%s", "tooltip": "%s"}\n' "$icon" "$class" "$tooltip"
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
            mac=$(bluetoothctl devices Paired | grep "$name" | awk '{print $2}')
            bluetoothctl disconnect "$mac"
            ;;
          "󰂯  "*)
            name="''${choice#󰂯  }"
            mac=$(bluetoothctl devices Paired | grep "$name" | awk '{print $2}')
            bluetoothctl connect "$mac"
            ;;
        esac
      done
    '';
  };

  # Curated help menu with common keybindings and an option to view all raw
  # bindings from hyprctl. Static content for reliability and readability.
  keybindingsHelp = pkgs.writeShellApplication {
    name = "hypr-keybindings-help";
    runtimeInputs = with pkgs; [hyprland jq rofi systemd coreutils];
    text = ''
            log() { echo "$*" | systemd-cat -t hypr-keybindings-help -p info; }

            show_all_bindings() {
              hyprctl binds -j | jq -r '.[] |
                ((.modmask // 0) as $m |
                  (if ($m % 2 >= 1) then "Shift+" else "" end) +
                  (if ($m % 4 >= 2) then "Ctrl+" else "" end) +
                  (if ($m % 8 >= 4) then "Alt+" else "" end) +
                  (if ($m % 16 >= 8) then "Super+" else "" end) +
                  (if ($m % 128 >= 64) then "Super+" else "" end)
                ) + .key + "  →  " + .dispatcher + " " + .arg' \
                | sort \
                | rofi -dmenu -i -p "All Keybindings" \
                    -theme-str 'listview { lines: 20; }' \
                    -theme-str 'window { width: 800px; }' \
                || true
            }

            help_text="── Common Actions ──
      Super                App Launcher
      Super+Q              Terminal
      Super+E              File Manager
      Super+C              Close Window
      Super+V              Toggle Floating
      Super+Backspace      Lock Screen
      Super+F1             This Help
      ── Window Management ──
      Super+Arrow          Move Focus
      Super+Shift+1-0      Move Window to Workspace
      Super+1-0            Switch Workspace (6+ creates new)
      Alt+Tab / Shift+Tab  Cycle Workspaces
      ── Session ──
      Super+Shift+R        Restart Session Services
      Super+Shift+M        Kill Session
      Super+Shift+S        Screenshot Region
      Super+Print          Screenshot Window
      Print                Screenshot Fullscreen
      ── Media ──
      Vol Up/Down          Volume
      Brightness Up/Down   Brightness
      ───────────
        All Keybindings"

            choice=$(echo "$help_text" \
              | rofi -dmenu -i -p "Help" \
                  -theme-str 'listview { lines: 15; }' \
                  -theme-str 'window { width: 800px; }') || exit 0
            log "selected: $choice"

            case "$choice" in
              *"All Keybindings"*) show_all_bindings ;;
            esac
    '';
  };

  # Restart key Hyprland session services when they get stuck.
  sessionRestart = pkgs.writeShellApplication {
    name = "hypr-session-restart";
    runtimeInputs = with pkgs; [systemd libnotify];
    text = ''
      log() { echo "$*" | systemd-cat -t hypr-session-restart -p info; }

      log "restarting session services"
      systemctl --user restart waybar.service
      systemctl --user restart hypridle.service
      systemctl --user restart swayosd.service
      notify-send "Session" "Services restarted"
    '';
  };

  # Screenshot with satty annotation. Accepts a mode argument: fullscreen,
  # region, or window. Saves to ~/Pictures/Screenshots and copies to clipboard.
  screenshot = pkgs.writeShellApplication {
    name = "hypr-screenshot";
    runtimeInputs = with pkgs; [grim slurp satty wl-clipboard hyprland jq systemd];
    text = ''
      log() { echo "$*" | systemd-cat -t hypr-screenshot -p info; }

      mkdir -p "$HOME/Pictures/Screenshots"
      mode="''${1:-region}"
      log "screenshot mode: $mode"
      case "$mode" in
        fullscreen)
          grim - | satty --filename - --output-filename "$HOME/Pictures/Screenshots/$(date +%Y%m%d_%H%M%S).png" --copy-command wl-copy
          ;;
        region)
          grim -g "$(slurp)" - | satty --filename - --output-filename "$HOME/Pictures/Screenshots/$(date +%Y%m%d_%H%M%S).png" --copy-command wl-copy
          ;;
        window)
          # Capture active window geometry from hyprctl
          geom=$(hyprctl activewindow -j | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
          grim -g "$geom" - | satty --filename - --output-filename "$HOME/Pictures/Screenshots/$(date +%Y%m%d_%H%M%S).png" --copy-command wl-copy
          ;;
      esac
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
  xdg.configFile."waybar/colors-dark.css".text = mkWaybarTheme colorsDark;
  xdg.configFile."waybar/colors-light.css".text = mkWaybarTheme colorsLight;

  # Nix-managed swayosd style variant files for the theme toggle.
  xdg.configFile."swayosd/style-dark.css".text = mkSwayosdTheme colorsDark;
  xdg.configFile."swayosd/style-light.css".text = mkSwayosdTheme colorsLight;

  # Nix-managed wallpaper variant files for the theme toggle.
  home.file.".config/wpaperd/wallpaper-dark.png".source = darkWallpaper;
  home.file.".config/wpaperd/wallpaper-light.png".source = lightWallpaper;

  # Nix-managed GTK color variant files for the theme toggle. Both GTK4 and
  # GTK3 with adw-gtk3 pick up @define-color overrides from user CSS.
  xdg.configFile."gtk-4.0/colors-dark.css".text = mkGtkTheme colorsDark;
  xdg.configFile."gtk-4.0/colors-light.css".text = mkGtkTheme colorsLight;

  # The gtk module generates gtk.css with an @import for adw-gtk3, but the
  # theme toggle seed script overwrites it with color definitions at runtime.
  # Without force, HM tries to back up the mutable file and fails when the
  # backup already exists from a previous activation.
  xdg.configFile."gtk-4.0/gtk.css".force = true;
  xdg.configFile."gtk-3.0/colors-dark.css".text = mkGtkTheme colorsDark;
  xdg.configFile."gtk-3.0/colors-light.css".text = mkGtkTheme colorsLight;

  wayland.windowManager.hyprland = {
    enable = true;
    settings = {
      "$mod" = "SUPER";
      "$terminal" = "alacritty";
      "$fileManager" = "nautilus";
      "$menu" = "rofi -show drun";

      exec-once = [
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
      ];
      # Scale 1.0 suits 1080p laptops like t14 and e470. HiDPI hosts override in
      # their host config via wayland.windowManager.hyprland.settings.monitor.
      monitor = ", preferred, auto, 1";

      env = [
        "XCURSOR_THEME,capitaine-cursors"
        "XCURSOR_SIZE,24"
        "HYPRCURSOR_SIZE,24"
      ];
      general = {
        gaps_in = 3;
        gaps_out = 8;
        "col.active_border" = "rgba(${colorsDark.base0D}30)";
        "col.inactive_border" = "rgba(${colorsDark.base0D}15)";
        border_size = 1;
        allow_tearing = true;
        resize_on_border = true;
      };
      decoration = {
        rounding = 4;
        rounding_power = 2.5;
        blur = {
          enabled = true;
          brightness = 1.0;
          contrast = 1.0;
          noise = 0.01;
          vibrancy = 0.2;
          vibrancy_darkness = 0.5;
          passes = 2;
          size = 5;
          popups = true;
          popups_ignorealpha = 0.2;
        };
        shadow = {
          enabled = false;
        };
      };
      animations = {
        enabled = true;
        animation = [
          "border, 1, 2, default"
          "fade, 1, 4, default"
          "windows, 1, 3, default, popin 80%"
          "workspaces, 1, 2, default, slide"
        ];
      };
      misc = {
        force_default_wallpaper = 0;
        animate_mouse_windowdragging = false;
        vrr = 1;
      };
      dwindle = {
        pseudotile = true;
        preserve_split = true;
      };
      # Create workspaces 1-5 at startup so Alt+Tab cycling always works.
      workspace = [
        "1, persistent:true"
        "2, persistent:true"
        "3, persistent:true"
        "4, persistent:true"
        "5, persistent:true"
      ];
      layerrule = [
        "noanim, waybar"
      ];
      xwayland.force_zero_scaling = true;
      input = {
        kb_layout = "us,cz";
        kb_variant = ",qwerty";
        touchpad = {
          natural_scroll = "true";
        };
      };
      # Keybinding conventions:
      #   $mod          = everyday actions: launch apps, switch workspaces, focus
      #   $mod+Shift    = destructive or sensitive: exit, move windows, restart, screenshot region
      #   ALT+Tab       = workspace cycling
      #   bindl         = media keys that work even when locked
      bind = [
        "$mod, Q, exec, $terminal"
        # Kill the entire Hyprland session
        "$mod SHIFT, M, exit,"
        "$mod, C, killactive,"
        "$mod, E, exec, $fileManager"
        "$mod, V, togglefloating,"
        "$mod, R, exec, $menu"
        # Dwindle layout controls
        "$mod, P, pseudo,"
        "$mod, J, togglesplit,"
        # Vim-style focus right. The hjk keys conflict with other bindings
        # so arrow keys cover all directions.
        "$mod, L, movefocus, r"
        # Cycle keyboard layout across all keyboards
        "$mod, space, exec, hyprctl switchxkblayout all next"
        # Lock screen
        "$mod, backspace, exec, loginctl lock-session"
        # Restart session services when waybar or hypridle gets stuck
        "$mod SHIFT, R, exec, ${lib.getExe sessionRestart}"
        # Show all keybindings in a searchable rofi list
        "$mod, F1, exec, ${lib.getExe keybindingsHelp}"
        # Screenshots via satty for annotation
        ", Print, exec, ${lib.getExe screenshot} fullscreen"
        "$mod SHIFT, S, exec, ${lib.getExe screenshot} region"
        "$mod, Print, exec, ${lib.getExe screenshot} window"
        # Cycle through workspaces on current monitor, wrapping around.
        "ALT, Tab, workspace, m+1"
        "ALT SHIFT, Tab, workspace, m-1"
        # Move focus with mainMod + arrow keys
        "$mod, left, movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up, movefocus, u"
        "$mod, down, movefocus, d"
        # Switch workspaces with mainMod + [0-9]
        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod, 6, workspace, 6"
        "$mod, 7, workspace, 7"
        "$mod, 8, workspace, 8"
        "$mod, 9, workspace, 9"
        "$mod, 0, workspace, 10"
        # Move active window to a workspace with mainMod + SHIFT + [0-9]
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        "$mod SHIFT, 6, movetoworkspace, 6"
        "$mod SHIFT, 7, movetoworkspace, 7"
        "$mod SHIFT, 8, movetoworkspace, 8"
        "$mod SHIFT, 9, movetoworkspace, 9"
        "$mod SHIFT, 0, movetoworkspace, 10"
      ];
      # Fire on key release so Super+Q still works without triggering rofi
      bindr = ["SUPER, Super_L, exec, $menu"];
      bindl = [
        ",XF86AudioRaiseVolume, exec, swayosd-client --output-volume raise --max-volume 150"
        ",XF86AudioLowerVolume, exec, swayosd-client --output-volume lower --max-volume 150"
        ",XF86AudioMute, exec, swayosd-client --output-volume mute-toggle"
        ",XF86AudioMicMute, exec, swayosd-client --input-volume mute-toggle"
        ",XF86MonBrightnessUp, exec, swayosd-client --brightness raise"
        ",XF86MonBrightnessDown, exec, swayosd-client --brightness lower"
      ];
    };
  };

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
        modules-right = ["privacy" "custom/dnd" "tray" "cpu" "memory" "custom/network" "bluetooth" "pulseaudio" "hyprland/language" "battery" "custom/darkmode" "custom/power"];

        "hyprland/workspaces" = {
          format = "{icon}";
          format-icons = {
            empty = "○";
            default = "●";
          };
          # Show app icons for known windows, filled dot for unknown apps
          window-rewrite-default = "●";
          window-rewrite = {
            "class<Alacritty>" = "󰆍";
            "class<firefox>" = "󰈹";
            "class<zen>" = "󰈹";
            "class<org.gnome.Nautilus>" = "󰝰";
            "class<Spotify>" = "󰓇";
            "class<discord>" = "󰙯";
            "class<vlc>" = "󰕼";
            "class<com.github.ADBeveridge.Raider>" = "󰩹";
          };
          on-click = "activate";
          on-scroll-up = "hyprctl dispatch workspace e-1";
          on-scroll-down = "hyprctl dispatch workspace e+1";
          persistent-workspaces."*" = 5;
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
          exec = ''mode=$(cat ~/.config/theme-mode 2>/dev/null || echo dark); if [ "$mode" = "light" ]; then echo "󰖨"; else echo "󰖔"; fi'';
          on-click = lib.getExe toggleTheme;
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
      exec = lib.getExe toggleTheme;
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

  # Application launcher themed from the base16 palette. The layout is a
  # static rasi file that imports a mutable colors.rasi swapped by the toggle.
  # We manage theme files directly instead of using programs.rofi.theme to
  # avoid fighting home-manager's structured rasi generation.
  programs.rofi = {
    enable = true;
    package = pkgs.rofi;
    terminal = "alacritty";
    extraConfig = {
      show-icons = true;
      icon-theme = "Adwaita";
      scroll-method = 1;
      # Vim navigation: clear conflicting defaults before rebinding
      kb-accept-entry = "Return,KP_Enter,Control+l";
      kb-remove-to-eol = "";
      kb-mode-complete = "";
      kb-row-up = "Up,Control+k,Control+p";
      kb-row-down = "Down,Control+j,Control+n";
      kb-cancel = "Escape,Control+bracketleft";
    };
    theme = "${xdgConfig}/rofi/theme.rasi";
  };

  # Nix-managed rofi color variant files for the theme toggle.
  xdg.configFile."rofi/colors-dark.rasi".text = mkRofiColors colorsDark;
  xdg.configFile."rofi/colors-light.rasi".text = mkRofiColors colorsLight;
  xdg.configFile."rofi/theme.rasi".text = rofiLayoutRasi;

  # Desktop notifications. The config is a mutable file managed by the theme
  # toggle script, not home-manager's structured settings. This avoids the bug
  # where makoctl reload ignores changes to included files.
  services.mako.enable = true;
  # Prevent home-manager from generating a config file. The toggle script and
  # activation seed manage ~/.config/mako/config directly.
  xdg.configFile."mako/config".enable = false;

  # Nix-managed mako config variant files for the theme toggle.
  xdg.configFile."mako/config-dark".text = mkMakoTheme colorsDark colorsDark.base0D;
  xdg.configFile."mako/config-light".text = mkMakoTheme colorsLight colorsLight.base0D;

  # On-screen display for volume and brightness media keys. Uses a mutable
  # CSS path so the day/night toggle can swap themes at runtime.
  services.swayosd = {
    enable = true;
    stylePath = "${config.xdg.configHome}/swayosd/style.css";
  };

  # Screen lock with blurred background
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        hide_cursor = true;
        grace = 5;
      };
      background = [
        {
          monitor = "";
          path = "screenshot";
          blur_passes = 3;
          blur_size = 8;
        }
      ];
      input-field = [
        {
          monitor = "";
          size = "300, 50";
          outline_thickness = 2;
          outer_color = "rgb(${colorsDark.base0D})";
          inner_color = "rgb(${colorsDark.base00})";
          font_color = "rgb(${colorsDark.base05})";
          fade_on_empty = true;
          placeholder_text = "";
          dots_center = true;
          position = "0, -20";
          halign = "center";
          valign = "center";
        }
      ];
    };
  };

  # Idle management: dim, lock, dpms off, suspend
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
      listener = [
        {
          timeout = 300;
          on-timeout = "brightnessctl -s set 10%";
          on-resume = "brightnessctl -r";
        }
        {
          timeout = 600;
          on-timeout = "loginctl lock-session";
        }
        {
          timeout = 900;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
        {
          timeout = 1800;
          on-timeout = "systemctl suspend";
        }
      ];
    };
  };

  gtk = {
    enable = true;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
  };

  home.pointerCursor = {
    name = "capitaine-cursors";
    package = pkgs.capitaine-cursors;
    size = 24;
    gtk.enable = true;
  };

  # Wallpaper daemon. Uses a mutable path so the day/night toggle can swap
  # wallpapers at runtime. The activation script seeds it with the dark variant.
  services.wpaperd = {
    enable = true;
    settings = {
      default = {
        path = "~/.config/wpaperd/current-wallpaper.png";
        mode = "center";
      };
    };
  };

  # Seed mutable theme files on every activation so nix config changes
  # propagate. Reads the current mode and copies the matching variant.
  # Removes targets first since they might be read-only nix store copies
  # or symlinks, both of which block writes.
  home.activation.seedThemeFiles = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mode=$(cat "$HOME/.config/theme-mode" 2>/dev/null || echo "dark")

    ${lib.concatMapStringsSep "\n" (
        t:
          lib.concatMapStringsSep "\n" (s: let
            # Replace literal ${mode} in the source template with the shell variable
            src = builtins.replaceStrings ["\${mode}"] [''"''${mode}"''] s.source;
          in ''
            rm -f "${s.target}"
            mkdir -p "$(dirname "${s.target}")"
            cat "${src}" > "${s.target}"
          '')
          t.seed
      )
      config.theme.toggle}
  '';

  theme.toggle = [
    {
      name = "waybar";
      switch = pkgs.writeShellApplication {
        name = "theme-switch-waybar";
        text = ''
          cat "${xdgConfig}/waybar/colors-$1.css" > "${xdgConfig}/waybar/colors.css"
        '';
      };
      seed = [
        {
          source = "${xdgConfig}/waybar/colors-\${mode}.css";
          target = "${xdgConfig}/waybar/colors.css";
        }
      ];
    }
    {
      name = "mako";
      switch = pkgs.writeShellApplication {
        name = "theme-switch-mako";
        runtimeInputs = [pkgs.mako];
        text = ''
          cat "${xdgConfig}/mako/config-$1" > "${xdgConfig}/mako/config"
          makoctl reload || true
        '';
      };
      seed = [
        {
          source = "${xdgConfig}/mako/config-\${mode}";
          target = "${xdgConfig}/mako/config";
        }
      ];
    }
    {
      name = "swayosd";
      switch = pkgs.writeShellApplication {
        name = "theme-switch-swayosd";
        runtimeInputs = [pkgs.systemd];
        text = ''
          cat "${xdgConfig}/swayosd/style-$1.css" > "${xdgConfig}/swayosd/style.css"
          systemctl --user restart swayosd.service || true
        '';
      };
      seed = [
        {
          source = "${xdgConfig}/swayosd/style-\${mode}.css";
          target = "${xdgConfig}/swayosd/style.css";
        }
      ];
    }
    {
      name = "wallpaper";
      switch = pkgs.writeShellApplication {
        name = "theme-switch-wallpaper";
        runtimeInputs = [pkgs.wpaperd];
        text = ''
          install -m 644 "${xdgConfig}/wpaperd/wallpaper-$1.png" "${xdgConfig}/wpaperd/current-wallpaper.png"
          wpaperctl reload || true
        '';
      };
      seed = [
        {
          source = "${xdgConfig}/wpaperd/wallpaper-\${mode}.png";
          target = "${xdgConfig}/wpaperd/current-wallpaper.png";
        }
      ];
    }
    {
      name = "rofi";
      switch = pkgs.writeShellApplication {
        name = "theme-switch-rofi";
        text = ''
          cat "${xdgConfig}/rofi/colors-$1.rasi" > "${xdgConfig}/rofi/colors.rasi"
        '';
      };
      seed = [
        {
          source = "${xdgConfig}/rofi/colors-\${mode}.rasi";
          target = "${xdgConfig}/rofi/colors.rasi";
        }
      ];
    }
    {
      name = "gtk-css";
      switch = pkgs.writeShellApplication {
        name = "theme-switch-gtk-css";
        text = ''
          cat "${xdgConfig}/gtk-4.0/colors-$1.css" > "${xdgConfig}/gtk-4.0/gtk.css"
          cat "${xdgConfig}/gtk-3.0/colors-$1.css" > "${xdgConfig}/gtk-3.0/gtk.css"
        '';
      };
      seed = [
        {
          source = "${xdgConfig}/gtk-4.0/colors-\${mode}.css";
          target = "${xdgConfig}/gtk-4.0/gtk.css";
        }
        {
          source = "${xdgConfig}/gtk-3.0/colors-\${mode}.css";
          target = "${xdgConfig}/gtk-3.0/gtk.css";
        }
      ];
    }
    {
      name = "claude-code";
      switch = pkgs.writeShellApplication {
        name = "theme-switch-claude-code";
        runtimeInputs = [pkgs.jq];
        # Only affects new sessions. Running instances cache the config.
        text = ''
          cfg="$HOME/.claude.json"
          [ -f "$cfg" ] || echo '{}' > "$cfg"
          jq --arg t "$1" '.theme = $t' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
        '';
      };
    }
    {
      name = "gsettings";
      switch = pkgs.writeShellApplication {
        name = "theme-switch-gsettings";
        runtimeInputs = [pkgs.glib];
        text = ''
          case "$1" in
            light)
              gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
              gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3'
              ;;
            *)
              gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
              gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
              ;;
          esac
        '';
      };
    }
  ];
}
