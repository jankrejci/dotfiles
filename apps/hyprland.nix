{
  wayland.windowManager.hyprland = {
    # enable = true;
    settings = {
      # "monitor" = [ "" "prefered" "auto" "auto" ];
      "$mod" = "SUPER";
      "$terminal" = "alacritty";
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
        rounding = 10;
        blur = {
          enabled = true;
          brightness = 1.0;
          contrast = 1.0;
          noise = 0.01;
          vibrancy = 0.2;
          vibrancy_darkness = 0.5;
          passes = 4;
          size = 7;
          popups = true;
          popups_ignorealpha = 0.2;
        };
      };
      bind = [
        "$mod, Q, exec, $terminal"
        "$mod, M, exit,"
        "$mod, C, killactive,"
        "$mod, E, exec, $fileManager"
        "$mod, V, togglefloating,"
        "$mod, R, exec, $menu"
        "$mod, P, pseudo, # dwindle"
        "$mod, J, togglesplit, # dwindle"
        "$mod, left, movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up, movefocus, u"
        "$mod, down, movefocus, d"
      ];
    };
  };
}
