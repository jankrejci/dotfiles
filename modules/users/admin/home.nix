{ ... }:

{
  home.username = "admin";
  home.homeDirectory = "/home/admin";

  imports = [
    ../../starship.nix # customizable prompt
    ../../git.nix # the git
    ../../helix-simple.nix # modal editor
    ../../zellij.nix # terminal multiplexer
    ../../nushell.nix # new type of shell
    ../../broot.nix # a better way to navigate directories
    ../../carapace.nix
  ];

  fonts.fontconfig.enable = true;

  programs.home-manager.enable = true;

  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "24.11";
}
