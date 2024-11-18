{ pkgs, ... }:

{
  programs.broot = {
    enable = true;
    package = pkgs.unstable.broot;
    settings = {
      icon_theme = "nerdfont";
    };
  };
}

