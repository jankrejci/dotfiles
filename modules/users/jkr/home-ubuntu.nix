{ pkgs, ... }:
{
  home.username = "jkr";
  home.homeDirectory = "/home/jkr";

  nixGL.packages = pkgs.nixgl;
  nixGL.defaultWrapper = "mesa";
  nixGL.installScripts = [ "mesa" ];

  imports = [
    ../../alacritty.nix # accelerated terminal emulator
    ../../starship.nix # customizable prompt
    ../../git.nix # the git
    ../../helix.nix # modal editor
    ../../zellij.nix # terminal multiplexer
    ../../nushell.nix # new type of shell
    ../../broot.nix # a better way to navigate directories
    ../../carapace.nix # multi-shell completion library
  ];

  home.packages = with pkgs; [
    unstable.shell-gpt # cli gpt prompt
    unstable.rustup # rust install tool
    unstable.espflash # flasher utility for Espressif SoCs 
    unstable.prusa-slicer # slicer for 3D printing
    nixgl.auto.nixGLDefault # opengl wrapper for non-nixos distro
    curl
    bash
    unzip
    wget
    coreutils
    rclone
    rsync
    jq
    vim
    neofetch
    usbutils
    pciutils
    lshw
    brightnessctl
    bat # cat clone with wings
    eza # ls replacement
    fd # find relplacement
    fzf # cli fuzzy finder
    zoxide # smarter cd command
    ripgrep # search tool 
    tealdeer # tldr help tool
    nmap # network mapper
    htop # interactive process viewer 
    rshell # remote shell for MicroPython 
    hexyl # cli hex viewer
    gitui # terminal-ui for git
    tokei # code statistics tool
    tealdeer # tldr help tool
    saleae-logic-2 # logic analyzer software
    ghidra-bin
  ];

  home.sessionVariables = {
    EDITOR = "hx";
  };

  programs.home-manager.enable = true;

  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "24.11";
}
