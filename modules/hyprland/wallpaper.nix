# Wallpaper and cursor
#
# - Generated wallpapers with centered Nix snowflake
# - wpaperd wallpaper daemon with mutable path for theme toggle
# - capitaine cursors
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
in {
  # Nix-managed wallpaper variant files for the theme toggle.
  home.file.".config/wpaperd/${config.colorScheme.themeName}-dark.png".source = darkWallpaper;
  home.file.".config/wpaperd/${config.colorScheme.themeName}-light.png".source = lightWallpaper;

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
  ];
}
