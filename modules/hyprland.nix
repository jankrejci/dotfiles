# Hyprland window manager for home-manager
#
# - waybar top bar with workspaces, system monitors, tray
# - hyprlock/hypridle for screen lock and idle management
# - mako notifications, wpaperd wallpaper, polkit agent
# - tiling with rofi launcher, workspace switching, media keys
# - GNOME remains as alternative session in GDM
{pkgs, ...}: let
  # Dark wallpaper generated from solid color to avoid committing a binary.
  # Resolution is arbitrary since the image is a uniform color.
  darkWallpaper =
    pkgs.runCommand "dark-wallpaper.png" {
      nativeBuildInputs = [pkgs.imagemagick];
    } ''
      magick -size 3840x2160 xc:'#1e1e2e' $out
    '';
in {
  wayland.windowManager.hyprland = {
    enable = true;
    settings = {
      "$mod" = "SUPER";
      "$terminal" = "alacritty";
      "$fileManager" = "nautilus";
      "$menu" = "rofi -show drun -show-icons";

      exec-once = [
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
      ];
      env = [
        "XCURSOR_SIZE,24"
        "HYPRCURSOR_SIZE,24"
      ];
      general = {
        gaps_in = 5;
        gaps_out = 5;
        border_size = 1;
        allow_tearing = false;
        resize_on_border = true;
      };
      decoration = {
        rounding = 5;
        blur = {
          enabled = true;
          brightness = 0.5;
          contrast = 0.5;
          noise = 0.01;
          vibrancy = 0.2;
          vibrancy_darkness = 0.5;
          passes = 4;
          size = 7;
          popups = true;
          popups_ignorealpha = 0.2;
        };
      };
      input = {
        kb_layout = "us";
        touchpad = {
          natural_scroll = "true";
        };
      };
      bind = [
        "$mod, Q, exec, $terminal"
        "$mod, M, exit,"
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
        # Lock screen
        "$mod, backspace, exec, loginctl lock-session"
        # Screenshot region to clipboard
        '', Print, exec, grim -g "$(slurp)" - | wl-copy''
        ''$mod SHIFT, S, exec, grim -g "$(slurp)" - | wl-copy''
        # Screenshot fullscreen to clipboard
        "$mod, Print, exec, grim - | wl-copy"
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

  # Top bar replicating GNOME dash-to-panel layout:
  # [workspaces]          [clock]          [cpu mem net audio battery tray]
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
        spacing = 8;
        modules-left = ["hyprland/workspaces"];
        modules-center = ["clock"];
        modules-right = ["cpu" "memory" "network" "pulseaudio" "battery" "tray"];

        "hyprland/workspaces" = {
          format = "{id}";
          on-click = "activate";
        };
        clock = {
          format = "{:%a %b %d  %H:%M}";
          tooltip-format = "{:%Y-%m-%d %H:%M:%S}";
        };
        cpu = {
          format = " {usage}%";
          interval = 5;
        };
        memory = {
          format = " {percentage}%";
          interval = 5;
        };
        network = {
          format-wifi = " {signalStrength}%";
          format-ethernet = " {ifname}";
          format-disconnected = "󰤭 disconnected";
          tooltip-format = "{ifname}: {ipaddr}/{cidr}";
        };
        pulseaudio = {
          format = "{icon} {volume}%";
          format-muted = " muted";
          format-icons = {
            default = ["" "" ""];
          };
          on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        };
        battery = {
          format = "{icon} {capacity}%";
          format-charging = " {capacity}%";
          format-icons = ["" "" "" "" ""];
          states = {
            warning = 20;
            critical = 10;
          };
        };
        tray = {
          spacing = 8;
        };
      }
    ];
    style = ''
      * {
        font-family: "DejaVuSansM Nerd Font", sans-serif;
        font-size: 13px;
        min-height: 0;
      }

      window#waybar {
        background-color: rgba(30, 30, 46, 0.9);
        color: #cdd6f4;
      }

      #workspaces button {
        padding: 0 8px;
        color: #6c7086;
        border-bottom: 2px solid transparent;
      }

      #workspaces button.active {
        color: #cdd6f4;
        border-bottom: 2px solid #89b4fa;
      }

      #workspaces button:hover {
        background: rgba(137, 180, 250, 0.2);
      }

      #clock,
      #cpu,
      #memory,
      #network,
      #pulseaudio,
      #battery,
      #tray {
        padding: 0 10px;
      }

      #battery.warning {
        color: #fab387;
      }

      #battery.critical {
        color: #f38ba8;
      }
    '';
  };

  # Desktop notifications
  services.mako = {
    enable = true;
    settings = {
      default-timeout = 5000;
      border-radius = 5;
      background-color = "#1e1e2edd";
      text-color = "#cdd6f4";
      border-color = "#89b4fa";
      border-size = 2;
      font = "DejaVuSansM Nerd Font 11";
    };
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
          outer_color = "rgb(89, 180, 250)";
          inner_color = "rgb(30, 30, 46)";
          font_color = "rgb(205, 214, 244)";
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

  # Wallpaper daemon
  services.wpaperd = {
    enable = true;
    settings = {
      default = {
        path = darkWallpaper;
        mode = "center";
      };
    };
  };
}
