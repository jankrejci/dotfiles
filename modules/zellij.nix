{ pkgs, ... }:
{
  programs.zellij = {
    enable = true;
    package = pkgs.unstable.zellij;
  };
  home.file.".config/zellij/config.kdl".text = ''
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
    theme "nord"
    default_layout "compact"
    scrollback_editor "hx"
  '';

  home.packages = with pkgs; [
    nerd-fonts.dejavu-sans-mono
  ];

  xdg.desktopEntries."Zellij" = {
    name = "Zellij";
    comment = "Terminal multiplexer";
    exec = "alacritty -e zellij -l welcome";
    icon = "/home/jkr/dotfiles/modules/zellij/logo.png";
    categories = [ "System" "TerminalEmulator" ];
    terminal = false;
  };

}
