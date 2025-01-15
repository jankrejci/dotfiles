{ lib, ... }:
{
  home.username = "paja";
  home.homeDirectory = "/home/paja";

  dconf.settings = with lib.hm.gvariant; {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
    "org/gnome/desktop/sound" = {
      allow-volume-above-100-percent = true;
    };
    # Generated via dconf2nix: https://github.com/nix-commmunity/dconf2nix
    "org/gnome/desktop/input-sources" = {
      mru-sources = [
        (mkTuple [ "xkb" "us" ])
        (mkTuple [ "xkb" "cz+qwertz" ])
      ];
      sources = [
        (mkTuple [ "xkb" "us" ])
        (mkTuple [ "xkb" "cz+qwertz" ])
      ];
      xkb-options = [ ];
    };
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # This value determines the Home Manager release that your
  # configuration is compatible with. It's recommended to keep this up to date.
  home.stateVersion = "24.11";
}
