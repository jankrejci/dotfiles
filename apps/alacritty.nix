{
  programs.alacritty = {
    enable = true;
    settings = {
      font.normal.family = "DejaVuSansMono NF";
      window.decorations = "None";
    };
  };

  xdg.desktopEntries."Alacritty" = {
    name = "Alacritty";
    comment = "Terminal emulator";
    icon = "Alacritty";
    exec = "nixGL alacritty";
    categories = [ "TerminalEmulator" ];
    terminal = false;
    mimeType = [ "text/plain" ];
  };

}
