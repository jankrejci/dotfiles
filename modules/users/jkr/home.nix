{ pkgs, ... }:

{
  home.username = "jkr";
  home.homeDirectory = "/home/jkr";

  imports = [
    ../../alacritty.nix # accelerated terminal emulator
    ../../starship.nix # customizable prompt
    ../../git.nix # the git
    ../../helix.nix # modal editor
    ../../zellij.nix # terminal multiplexer
    ../../nushell.nix # new type of shell
    ../../broot.nix # a better way to navigate directories
    ../../hyprland.nix # tiling window manager
    ../../carapace.nix # multi-shell completion library
  ];

  home.packages = with pkgs; [
    unstable.shell-gpt # cli gpt prompt
    unstable.rustup # rust install tool
    unstable.espflash # flasher utility for Espressif SoCs 
    unstable.prusa-slicer # slicer for 3D printing
    gnomeExtensions.vitals
    gnomeExtensions.dash-to-panel
    rshell # remote shell for MicroPython 
    tokei # code statistics tool
    tealdeer # tldr help tool
    saleae-logic-2 # logic analyzer software
    kicad
  ];

  fonts.fontconfig.enable = true;

  home.sessionVariables = {
    EDITOR = "hx";
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
    "org/gnome/desktop/sound" = {
      allow-volume-above-100-percent = true;
    };
    "org/gnome/shell" = {
      disable-user-extensions = false;

      # `gnome-extensions list` for a list
      enabled-extensions = [
        "Vitals@CoreCoding.com"
        "dash-to-panel@jderose9.github.com"
      ];
    };
  };

  programs.home-manager.enable = true;

  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "24.11";
}
