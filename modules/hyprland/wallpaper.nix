# Wallpaper, GTK theme, and cursor
#
# - Generated wallpapers with centered Nix snowflake
# - GTK @define-color overrides for libadwaita named colors
# - adw-gtk3 for GTK3 apps, capitaine cursors
# - wpaperd wallpaper daemon with mutable path for theme toggle
{
  pkgs,
  config,
  ...
}: let
  colorsDark = config.colorScheme.darkPalette;
  colorsLight = config.colorScheme.lightPalette;
  xdgConfig = config.xdg.configHome;

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
in {
  # Nix-managed wallpaper variant files for the theme toggle.
  home.file.".config/wpaperd/${config.colorScheme.themeName}-dark.png".source = darkWallpaper;
  home.file.".config/wpaperd/${config.colorScheme.themeName}-light.png".source = lightWallpaper;

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

  # Wallpaper daemon. Uses a mutable path so the theme toggle can swap
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

  theme.toggle = [
    {
      name = "wallpaper";
      switch = pkgs.writeShellApplication {
        name = "theme-switch-wallpaper";
        runtimeInputs = [pkgs.wpaperd];
        text = ''
          install -m 644 "${xdgConfig}/wpaperd/${config.colorScheme.themeName}-$1.png" "${xdgConfig}/wpaperd/current-wallpaper.png"
          wpaperctl reload || true
        '';
      };
      seed = [
        {
          source = "${xdgConfig}/wpaperd/${config.colorScheme.themeName}-\${mode}.png";
          target = "${xdgConfig}/wpaperd/current-wallpaper.png";
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
  ];
}
