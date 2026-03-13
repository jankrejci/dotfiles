# Alacritty terminal emulator for home-manager
#
# - base16 color themes from nix-colors palette
# - two variant files for dark/light theme toggle
# - desktop entry for rofi launcher
{
  pkgs,
  config,
  ...
}: let
  colorsDark = config.colorScheme.darkPalette;
  colorsLight = config.colorScheme.lightPalette;

  # Generate Alacritty theme TOML from a base16 palette.
  mkAlacrittyTheme = p: ''
    [colors.primary]
    background = "#${p.base00}"
    foreground = "#${p.base05}"

    [colors.cursor]
    text = "#${p.base00}"
    cursor = "#${p.base0D}"

    [colors.normal]
    black = "#${p.base00}"
    red = "#${p.base08}"
    green = "#${p.base0B}"
    yellow = "#${p.base0A}"
    blue = "#${p.base0D}"
    magenta = "#${p.base0E}"
    cyan = "#${p.base0C}"
    white = "#${p.base05}"

    [colors.bright]
    black = "#${p.base03}"
    red = "#${p.base08}"
    green = "#${p.base0B}"
    yellow = "#${p.base0A}"
    blue = "#${p.base0D}"
    magenta = "#${p.base0E}"
    cyan = "#${p.base0C}"
    white = "#${p.base07}"
  '';
in {
  programs.alacritty = {
    enable = true;
    package = pkgs.alacritty;
    settings = {
      # Dark variant first as fallback, mutable file overrides when present.
      general.import = [
        "~/.config/alacritty/${config.colorScheme.themeName}-dark.toml"
        "~/.config/alacritty/colors.toml"
      ];
      font = {
        normal = {
          family = "DejaVuSansM Nerd Font Mono";
          style = "Regular";
        };
        bold = {
          family = "DejaVuSansM Nerd Font Mono";
          style = "Bold";
        };
        italic = {
          family = "DejaVuSansM Nerd Font Mono";
          style = "Oblique";
        };
      };
      window = {
        decorations = "None";
        startup_mode = "Maximized";
        padding = {
          x = 4;
          y = 4;
        };
      };
    };
  };

  xdg.desktopEntries."Alacritty" = {
    name = "Alacritty";
    comment = "Terminal emulator";
    icon = "Alacritty";
    exec = "alacritty";
    categories = ["TerminalEmulator"];
    terminal = false;
    mimeType = ["text/plain"];
  };

  # Nix-managed alacritty color variant files for the theme toggle.
  # The mutable colors.toml is written by the activation script.
  home.file.".config/alacritty/${config.colorScheme.themeName}-dark.toml".text = mkAlacrittyTheme colorsDark;
  home.file.".config/alacritty/${config.colorScheme.themeName}-light.toml".text = mkAlacrittyTheme colorsLight;

  theme.toggle = [
    {
      name = "alacritty";
      switch = pkgs.writeShellApplication {
        name = "theme-switch-alacritty";
        text = ''
          cat "${config.xdg.configHome}/alacritty/${config.colorScheme.themeName}-$1.toml" > "${config.xdg.configHome}/alacritty/colors.toml"
        '';
      };
      seed = [
        {
          source = "${config.xdg.configHome}/alacritty/${config.colorScheme.themeName}-\${mode}.toml";
          target = "${config.xdg.configHome}/alacritty/colors.toml";
        }
      ];
    }
  ];
}
