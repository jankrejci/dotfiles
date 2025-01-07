{ pkgs, ... }:

{
  programs.alacritty = {
    enable = true;
    package = pkgs.unstable.alacritty;
    settings = {
      font.normal.family = "DejaVuSansMono";
      window = {
        decorations = "None";
        startup_mode = "Maximized";
      };
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
