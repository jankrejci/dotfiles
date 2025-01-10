{ pkgs, config, ... }:
let
  nixGL = import ./nixGL.nix { inherit pkgs config; };
in
{
  imports = [
    ./options.nix
  ];

  programs.alacritty = {
    enable = true;
    package = (nixGL pkgs.unstable.alacritty);
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
    exec = "alacritty";
    categories = [ "TerminalEmulator" ];
    terminal = false;
    mimeType = [ "text/plain" ];
  };

}
