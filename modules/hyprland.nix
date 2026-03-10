# Hyprland window manager for home-manager
#
# - tiling with workspace switching and media keys
# - GNOME remains as alternative session in GDM
{
  pkgs,
  config,
  ...
}: let
  colorsDark = config.colorScheme.palette;
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
        ",XF86AudioRaiseVolume, exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"
        ",XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ",XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ",XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
        ",XF86MonBrightnessUp, exec, brightnessctl s 10%+"
        ",XF86MonBrightnessDown, exec, brightnessctl s 10%-"
      ];
    };
  };

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
}
