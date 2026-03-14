# Zellij terminal multiplexer for home-manager
#
# - base16 color themes from nix-colors palette
# - config variant files with different active themes
# - desktop entry and icon for rofi launcher
#
# Zellij has no API to switch themes in running sessions. The toggle swaps
# config.kdl which zellij auto-reloads since 0.41. Config must be a regular
# file because zellij ignores symlinks.
# See: https://github.com/zellij-org/zellij/issues/3879
{
  pkgs,
  config,
  ...
}: let
  colorsDark = config.colorScheme.darkPalette;
  colorsLight = config.colorScheme.lightPalette;
  themeName = config.colorScheme.themeName;

  # Generate Zellij config.kdl with the given active theme name.
  mkZellijConfig = activeTheme: ''
    keybinds {
        pane {
          bind "_" { NewPane "Down"; SwitchToMode "Normal"; }
          bind "|" { NewPane "Right"; SwitchToMode "Normal"; }
          bind "r" { SwitchToMode "RenamePane"; PaneNameInput 0;}
        }
        tab {
          bind "Ctrl t" { SwitchToMode "Normal"; }
        }
    }
    default_shell "nu"
    theme "${activeTheme}"
    default_layout "compact"
    scrollback_editor "hx"
  '';

  # Generate a Zellij component-based theme file from a base16 palette.
  # Component format gives per-element control over frame and tab colors.
  mkZellijTheme = name: p: ''
    themes {
      ${name} {
        text_unselected {
          base "#${p.base03}"
          background "#${p.panelBg}"
          emphasis_0 "#${p.base09}"
          emphasis_1 "#${p.base0C}"
          emphasis_2 "#${p.base0B}"
          emphasis_3 "#${p.base0E}"
        }
        text_selected {
          base "#${p.base06}"
          background "#${p.base00}"
          emphasis_0 "#${p.base09}"
          emphasis_1 "#${p.base0C}"
          emphasis_2 "#${p.base0B}"
          emphasis_3 "#${p.base0E}"
        }
        ribbon_unselected {
          base "#${p.base03}"
          background "#${p.base00}"
          emphasis_0 "#${p.base0D}"
          emphasis_1 "#${p.base08}"
          emphasis_2 "#${p.base0C}"
          emphasis_3 "#${p.base0E}"
        }
        ribbon_selected {
          base "#${p.base01}"
          background "#${p.base0D}"
          emphasis_0 "#${p.base0D}"
          emphasis_1 "#${p.base08}"
          emphasis_2 "#${p.base0B}"
          emphasis_3 "#${p.base0E}"
        }
        table_title {
          base "#${p.base06}"
          background 0
          emphasis_0 "#${p.base09}"
          emphasis_1 "#${p.base0C}"
          emphasis_2 "#${p.base0B}"
          emphasis_3 "#${p.base0E}"
        }
        table_cell_unselected {
          base "#${p.base06}"
          background "#${p.base01}"
          emphasis_0 "#${p.base09}"
          emphasis_1 "#${p.base0C}"
          emphasis_2 "#${p.base0B}"
          emphasis_3 "#${p.base0E}"
        }
        table_cell_selected {
          base "#${p.base06}"
          background "#${p.base00}"
          emphasis_0 "#${p.base09}"
          emphasis_1 "#${p.base0C}"
          emphasis_2 "#${p.base0B}"
          emphasis_3 "#${p.base0E}"
        }
        list_unselected {
          base "#${p.base06}"
          background "#${p.base01}"
          emphasis_0 "#${p.base09}"
          emphasis_1 "#${p.base0C}"
          emphasis_2 "#${p.base0B}"
          emphasis_3 "#${p.base0E}"
        }
        list_selected {
          base "#${p.base06}"
          background "#${p.base00}"
          emphasis_0 "#${p.base09}"
          emphasis_1 "#${p.base0C}"
          emphasis_2 "#${p.base0B}"
          emphasis_3 "#${p.base0E}"
        }
        frame_selected {
          base "#${p.base0D}"
          background 0
          emphasis_0 "#${p.base09}"
          emphasis_1 "#${p.base0C}"
          emphasis_2 "#${p.base0B}"
          emphasis_3 "#${p.base0E}"
        }
        frame_highlight {
          base "#${p.base09}"
          background 0
          emphasis_0 "#${p.base09}"
          emphasis_1 "#${p.base0C}"
          emphasis_2 "#${p.base0B}"
          emphasis_3 "#${p.base0E}"
        }
        exit_code_success {
          base "#${p.base0B}"
          background 0
          emphasis_0 "#${p.base09}"
          emphasis_1 "#${p.base0C}"
          emphasis_2 "#${p.base0B}"
          emphasis_3 "#${p.base0E}"
        }
        exit_code_error {
          base "#${p.base08}"
          background 0
          emphasis_0 "#${p.base09}"
          emphasis_1 "#${p.base0C}"
          emphasis_2 "#${p.base0B}"
          emphasis_3 "#${p.base0E}"
        }
        multiplayer_user_colors {
          player_1 "#${p.base0E}"
          player_2 "#${p.base0D}"
          player_3 "#${p.base0A}"
          player_4 "#${p.base08}"
          player_5 "#${p.base0C}"
          player_6 "#${p.base09}"
          player_7 "#${p.base0B}"
          player_8 "#${p.base0F}"
        }
      }
    }
  '';
in {
  programs.zellij = {
    enable = true;
    package = pkgs.unstable.zellij;
  };

  # Nix-managed theme files, one per variant.
  home.file.".config/zellij/themes/${themeName}-dark.kdl".text = mkZellijTheme "${themeName}-dark" colorsDark;
  home.file.".config/zellij/themes/${themeName}-light.kdl".text = mkZellijTheme "${themeName}-light" colorsLight;

  # Config variant files with different active themes. The mutable config.kdl
  # is a regular file written by the seed service and swapped by the toggle.
  home.file.".config/zellij/${themeName}-dark.kdl".text = mkZellijConfig "${themeName}-dark";
  home.file.".config/zellij/${themeName}-light.kdl".text = mkZellijConfig "${themeName}-light";

  # Copy zellij logo to icons directory for desktop entry
  home.file.".local/share/icons/hicolor/128x128/apps/zellij.png".source = ../assets/zellij/logo.png;

  xdg.desktopEntries."Zellij" = {
    name = "Zellij";
    comment = "Terminal multiplexer";
    exec = "alacritty -e zellij -l welcome";
    icon = "zellij";
    categories = ["System" "TerminalEmulator"];
    terminal = false;
  };

  theme.toggle = [
    {
      name = "zellij";
      switch = pkgs.writeShellApplication {
        name = "theme-switch-zellij";
        text = ''
          cat "${config.xdg.configHome}/zellij/${themeName}-$1.kdl" > "${config.xdg.configHome}/zellij/config.kdl"
        '';
      };
      seed = [
        {
          source = "${config.xdg.configHome}/zellij/${themeName}-\${mode}.kdl";
          target = "${config.xdg.configHome}/zellij/config.kdl";
        }
      ];
    }
  ];
}
