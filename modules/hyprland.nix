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
    };
  };
}
