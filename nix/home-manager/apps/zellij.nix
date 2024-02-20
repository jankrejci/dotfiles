{
  programs.zellij = {
    enable = true;
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
}
