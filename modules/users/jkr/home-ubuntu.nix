{ pkgs, config, ... }:
let
  nixGL = import ../../nixGL.nix { inherit pkgs config; };
in
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
    ../../carapace.nix
  ];

  home.packages = with pkgs; [
    (nixGL unstable.alacritty)
    unstable.zellij
    unstable.helix
    unstable.nushell
    unstable.broot
    starship
    powerline-fonts # patched fonts used for zellij
    (pkgs.nerdfonts.override { fonts = [ "DejaVuSansMono" ]; }) # iconic fonts
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
    git
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
    nmap
    htop
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
    unstable.prusa-slicer # slicer for 3D printing
    saleae-logic-2 # logic analyzer software
    nixgl.auto.nixGLDefault # opengl wrapper for non-nixos distro
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
