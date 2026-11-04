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

  # Single source of truth so hyprctl in helper scripts always matches the
  # running compositor.
  hyprlandPackage = config.wayland.windowManager.hyprland.package;

  inherit (lib.generators) mkLuaInline;

  mod = "SUPER";
  terminal = "alacritty";
  fileManager = "nautilus";
  menu = "rofi -show drun";

  # Bind helpers rendering to hl.bind(keys, dispatcher, opts).
  # The Lua dispatcher text doubles as the description because hyprctl binds
  # no longer exposes dispatcher arguments, only an opaque function reference.
  bindWith = opts: keys: dispatcher: {
    _args = [keys (mkLuaInline dispatcher) (opts // {description = dispatcher;})];
  };
  bind = bindWith {};
  exec = keys: cmd: bind keys "hl.dsp.exec_cmd(${builtins.toJSON cmd})";
  workspaces = lib.range 1 9;

  # Curated help menu with common keybindings and an option to view all raw
  # bindings from hyprctl. Static content for reliability and readability.
  keybindingsHelp = pkgs.writeShellApplication {
    name = "hypr-keybindings-help";
    runtimeInputs = [hyprlandPackage] ++ (with pkgs; [jq rofi systemd coreutils]);
    text = ''
      log() { echo "$*" | systemd-cat -t hypr-keybindings-help -p info; }

      show_all_bindings() {
        hyprctl binds -j | jq -r '.[] |
          ((.modmask // 0) as $m |
            (if ($m % 2 >= 1) then "Shift+" else "" end) +
            (if (($m / 4 | floor) % 2 == 1) then "Ctrl+" else "" end) +
            (if (($m / 8 | floor) % 2 == 1) then "Alt+" else "" end) +
            (if (($m / 64 | floor) % 2 == 1) then "Super+" else "" end)
          ) + .key + "  →  " + .description' \
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
    runtimeInputs = [hyprlandPackage] ++ (with pkgs; [grim slurp satty wl-clipboard jq systemd]);
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
    package = pkgs.unstable.hyprland;
    # The NixOS module installs the portal. Home Manager would call .override
    # { hyprland = ...; } on it, which the unstable portal no longer accepts.
    portalPackage = null;
    # Hyprland 0.57 dropped hyprlang, so the config is rendered as Lua.
    configType = "lua";
    settings = {
      on = {
        _args = [
          "hyprland.start"
          (mkLuaInline ''
            function()
              hl.exec_cmd("${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1")
            end'')
        ];
      };
      # Default fallback for unconfigured monitors. Per-monitor settings are
      # managed via nwg-displays and loaded from monitors.lua in extraConfig.
      monitor = {
        output = "";
        mode = "preferred";
        position = "auto";
        scale = 1;
      };

      env = [
        {_args = ["XCURSOR_THEME" "capitaine-cursors"];}
        {_args = ["XCURSOR_SIZE" "24"];}
        {_args = ["HYPRCURSOR_SIZE" "24"];}
      ];
      config = {
        general = {
          gaps_in = 3;
          gaps_out = 8;
          col = {
            active_border = "rgba(${colorsDark.base0D}30)";
            inactive_border = "rgba(${colorsDark.base0D}15)";
          };
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
        };
        cursor = {
          # Lua config rejects values above 20, the former 60 was out of range.
          inactive_timeout = 20;
        };
        misc = {
          force_default_wallpaper = 0;
          animate_mouse_windowdragging = false;
          vrr = 1;
        };
        dwindle = {
          preserve_split = true;
        };
        xwayland = {
          force_zero_scaling = true;
        };
        input = {
          kb_layout = "us,cz";
          kb_variant = ",qwerty";
          touchpad = {
            natural_scroll = true;
          };
        };
      };
      animation = [
        {
          leaf = "border";
          enabled = true;
          speed = 2;
          bezier = "default";
        }
        {
          leaf = "fade";
          enabled = true;
          speed = 4;
          bezier = "default";
        }
        {
          leaf = "windows";
          enabled = true;
          speed = 3;
          bezier = "default";
          style = "popin 80%";
        }
        {
          leaf = "workspaces";
          enabled = true;
          speed = 2;
          bezier = "default";
          style = "slide";
        }
      ];
      # Create workspaces 1-3 at startup so Alt+Tab cycling always works.
      workspace_rule = map (n: {
        workspace = toString n;
        persistent = true;
      }) (lib.range 1 3);
      layer_rule = {
        name = "waybar-no-anim";
        match.namespace = "waybar";
        no_anim = true;
      };
      # Keybinding conventions:
      #   mod           = everyday actions: launch apps, switch workspaces, focus
      #   mod+Shift     = destructive or sensitive: exit, move windows, restart, screenshot region
      #   ALT+Tab       = workspace cycling
      #   locked        = media keys that work even when locked
      bind =
        [
          (exec "${mod} + Q" terminal)
          # Kill the entire Hyprland session
          (bind "${mod} + SHIFT + M" "hl.dsp.exit()")
          (bind "${mod} + C" "hl.dsp.window.close()")
          (exec "${mod} + E" fileManager)
          (bind "${mod} + V" ''hl.dsp.window.float({ action = "toggle" })'')
          (exec "${mod} + R" menu)
          # Dwindle layout controls
          (bind "${mod} + P" "hl.dsp.window.pseudo()")
          (bind "${mod} + J" ''hl.dsp.layout("togglesplit")'')
          # Cycle keyboard layout across all keyboards
          (exec "${mod} + space" "hyprctl switchxkblayout all next")
          # Lock screen
          (exec "${mod} + backspace" "loginctl lock-session")
          # Restart session services when waybar or hypridle gets stuck
          (exec "${mod} + SHIFT + R" (lib.getExe sessionRestart))
          # Show all keybindings in a searchable rofi list
          (exec "${mod} + F1" (lib.getExe keybindingsHelp))
          # Screenshots via satty for annotation
          (exec "Print" "${lib.getExe screenshot} fullscreen")
          (exec "${mod} + SHIFT + S" "${lib.getExe screenshot} region")
          (exec "${mod} + Print" "${lib.getExe screenshot} window")
          # Cycle through workspaces on current monitor, wrapping around.
          (bind "ALT + Tab" ''hl.dsp.focus({ workspace = "m+1" })'')
          (bind "ALT + SHIFT + Tab" ''hl.dsp.focus({ workspace = "m-1" })'')
          # Cycle workspaces on current monitor with mod + arrow/vim keys.
          # The j and k keys conflict with other bindings, so arrow keys
          # cover focus movement in all directions.
          (bind "${mod} + left" ''hl.dsp.focus({ workspace = "m-1" })'')
          (bind "${mod} + right" ''hl.dsp.focus({ workspace = "m+1" })'')
          (bind "${mod} + h" ''hl.dsp.focus({ workspace = "m-1" })'')
          (bind "${mod} + l" ''hl.dsp.focus({ workspace = "m+1" })'')
          # Move focus between tiled windows
          (bind "${mod} + up" ''hl.dsp.focus({ direction = "up" })'')
          (bind "${mod} + down" ''hl.dsp.focus({ direction = "down" })'')
        ]
        # Switch workspaces with mod + [1-9]
        ++ map (n: bind "${mod} + ${toString n}" "hl.dsp.focus({ workspace = ${toString n} })") workspaces
        # Move active window to workspace with mod + SHIFT + [1-9]
        ++ map (n: bind "${mod} + SHIFT + ${toString n}" "hl.dsp.window.move({ workspace = ${toString n} })") workspaces
        # Fire on key release so Super+Q still works without triggering rofi
        ++ [(bindWith {release = true;} "SUPER + Super_L" "hl.dsp.exec_cmd(${builtins.toJSON menu})")]
        ++ map (m: bindWith {locked = true;} m.key "hl.dsp.exec_cmd(${builtins.toJSON m.cmd})") [
          {
            key = "XF86AudioRaiseVolume";
            cmd = "swayosd-client --output-volume raise --max-volume 150";
          }
          {
            key = "XF86AudioLowerVolume";
            cmd = "swayosd-client --output-volume lower --max-volume 150";
          }
          {
            key = "XF86AudioMute";
            cmd = "swayosd-client --output-volume mute-toggle";
          }
          {
            key = "XF86AudioMicMute";
            cmd = "swayosd-client --input-volume mute-toggle";
          }
          {
            key = "XF86MonBrightnessUp";
            cmd = "swayosd-client --brightness raise";
          }
          {
            key = "XF86MonBrightnessDown";
            cmd = "swayosd-client --brightness lower";
          }
        ];
    };
    # nwg-displays writes monitors.lua. Load it only when it exists so a host
    # without a saved layout still starts with the fallback rule above.
    extraConfig = ''
      local monitors = os.getenv("HOME") .. "/.config/hypr/monitors.lua"
      local file = io.open(monitors, "r")
      if file then
        file:close()
        dofile(monitors)
      end
    '';
  };
}
