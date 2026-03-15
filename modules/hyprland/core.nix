# Hyprland window manager core configuration
#
# - tiling window manager settings and keybindings
# - polkit authentication agent
# - screenshot tool with satty annotation
# - session restart helper
# - keybindings help overlay
{
  pkgs,
  lib,
  config,
  ...
}: let
  colorsDark = config.colorScheme.darkPalette;

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
            (if ($m % 16 >= 8) then "Super+" else "" end)
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
        Super+Left/Right/H/L Cycle Workspaces
        Super+Up/Down        Move Focus
        Super+Shift+1-9      Move Window to Workspace
        Super+1-9            Switch Workspace
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
in {
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
      # Default fallback for unconfigured monitors. Per-monitor settings are
      # managed via nwg-displays and sourced from monitors.conf.
      monitor = ", preferred, auto, 1";
      source = ["~/.config/hypr/monitors.conf"];

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
      # Create workspaces 1-3 at startup so Alt+Tab cycling always works.
      workspace = [
        "1, persistent:true"
        "2, persistent:true"
        "3, persistent:true"
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
        # Cycle workspaces on current monitor with mainMod + arrow/vim keys.
        "$mod, left, workspace, m-1"
        "$mod, right, workspace, m+1"
        "$mod, h, workspace, m-1"
        "$mod, l, workspace, m+1"
        # Move focus between tiled windows
        "$mod, up, movefocus, u"
        "$mod, down, movefocus, d"
        # Switch workspaces with mainMod + [1-9]
        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod, 6, workspace, 6"
        "$mod, 7, workspace, 7"
        "$mod, 8, workspace, 8"
        "$mod, 9, workspace, 9"
        # Move active window to workspace with mainMod + SHIFT + [1-9]
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        "$mod SHIFT, 6, movetoworkspace, 6"
        "$mod SHIFT, 7, movetoworkspace, 7"
        "$mod SHIFT, 8, movetoworkspace, 8"
        "$mod SHIFT, 9, movetoworkspace, 9"
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
}
