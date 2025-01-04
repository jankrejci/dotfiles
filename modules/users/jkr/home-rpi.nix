{ pkgs, ... }:

{
  home.username = "jkr";
  home.homeDirectory = "/home/jkr";

  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "24.05";

  imports = [
    ../../alacritty.nix # accelerated terminal emulator
    ../../starship.nix # customizable prompt
    ../../git.nix # the git
    ../../helix.nix # modal editor
    ../../zellij.nix # terminal multiplexer
    ../../nushell.nix # new type of shell
    ../../broot.nix # a better way to navigate directories
  ];

  nixpkgs.config.allowUnfree = true;
  home.packages = with pkgs; [
    rshell
    hexyl # cli hex viewer
    gitui # terminal-ui for git
    tokei # code statistics tool
    tealdeer # tldr help tool
    unstable.shell-gpt # cli gpt prompt
    unstable.rustup # rust install tool
    git-absorb # absorb git hunks within existing commits
    delta # syntax highlighting diff
    unstable.espflash
    unstable.carapace # terminal command auto complete
  ];

  fonts.fontconfig.enable = true;

  programs.home-manager.enable = true;
}
