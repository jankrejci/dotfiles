# Rofi application launcher themed from the base16 palette
#
# The layout is a static rasi file that imports a mutable colors.rasi swapped
# by the toggle. We manage theme files directly instead of using
# programs.rofi.theme to avoid fighting home-manager's structured rasi
# generation.
{
  pkgs,
  config,
  ...
}: let
  colorsDark = config.colorScheme.darkPalette;
  colorsLight = config.colorScheme.lightPalette;
  xdgConfig = config.xdg.configHome;

  # Generate rofi color variable definitions as a rasi fragment.
  mkRofiTheme = p: ''
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
in {
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
  xdg.configFile."rofi/${config.colorScheme.themeName}-dark.rasi".text = mkRofiTheme colorsDark;
  xdg.configFile."rofi/${config.colorScheme.themeName}-light.rasi".text = mkRofiTheme colorsLight;
  xdg.configFile."rofi/theme.rasi".text = rofiLayoutRasi;

  theme.toggle = [
    {
      name = "rofi";
      switch = pkgs.writeShellApplication {
        name = "theme-switch-rofi";
        text = ''
          cat "${xdgConfig}/rofi/${config.colorScheme.themeName}-$1.rasi" > "${xdgConfig}/rofi/colors.rasi"
        '';
      };
      seed = [
        {
          source = "${xdgConfig}/rofi/${config.colorScheme.themeName}-\${mode}.rasi";
          target = "${xdgConfig}/rofi/colors.rasi";
        }
      ];
    }
  ];
}
