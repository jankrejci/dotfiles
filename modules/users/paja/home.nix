{ config, pkgs, ... }:

{
  home.username = "paja";
  home.homeDirectory = "/home/paja";

  # Packages for the family user
  home.packages = with pkgs; [
  ];

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
    "org/gnome/desktop/sound" = {
      allow-volume-above-100-percent = true;
    };
  };

  # This value determines the Home Manager release that your
  # configuration is compatible with. It's recommended to keep this up to date.
  home.stateVersion = "24.05";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
