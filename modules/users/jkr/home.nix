{ pkgs, lib, ... }:
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
    unstable.kicad-small
    gnomeExtensions.vitals
    gnomeExtensions.dash-to-panel
    rshell # remote shell for MicroPython 
    tokei # code statistics tool
    tealdeer # tldr help tool
    zen-browser
    # saleae-logic-2 # logic analyzer software
    # ghidra-bin
  ];

  fonts.fontconfig.enable = true;

  home.sessionVariables = {
    EDITOR = "hx";
  };

  # TODO add more configurations for power management and for panel position
  dconf.settings = with lib.hm.gvariant; {
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
    # Generated via dconf2nix: https://github.com/nix-commmunity/dconf2nix
    "org/gnome/desktop/input-sources" = {
      mru-sources = [
        (mkTuple [ "xkb" "us" ])
        (mkTuple [ "xkb" "cz+qwerty" ])
      ];
      sources = [
        (mkTuple [ "xkb" "us" ])
        (mkTuple [ "xkb" "cz+qwerty" ])
      ];
      xkb-options = [ ];
    };
    "org/gnome/settings-daemon/plugins/power" = {
      sleep-inactive-ac-type = "nothing";
      sleep-inactive-battery-type = "suspend";
      sleep-inactive-battery-timeout = 3600;
    };
    "org/gnome/desktop/session" = {
      idle-delay = 1800;
    };
    "org/gnome/desktop/interface" = {
      show-battery-percentage = true;
    };
    "org/gnome/shell" = {
      favorite-apps = [ "Alacritty.desktop" "firefox.desktop" ];
    };
    "org/gnome/shell/extensions/dash-to-panel" = {
      panel-positions = ''
        {"0":"TOP"}
      '';
    };

  };

  programs.home-manager.enable = true;

  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "24.11";
}
