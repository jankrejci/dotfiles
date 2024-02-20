{ config, pkgs, ... }:

{
  home.username = "jkr";
  home.homeDirectory = "/home/jkr";

  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.11";

  imports = [
    ./apps/alacritty.nix
    ./apps/starship.nix
    ./apps/git.nix
    ./apps/helix.nix
    ./apps/zellij.nix
  ];

  nixpkgs.config.allowUnfree = true;
  home.packages = with pkgs; [
    hexyl
    bat
    eza
    fd
    fzf
    zoxide
    marksman
    nil
    rustup
    delta
    taplo
    shfmt
    nixpkgs-fmt
    nodePackages.bash-language-server
    python311Packages.python-lsp-server
    (pkgs.nerdfonts.override { fonts = [ "DejaVuSansMono" ]; })
    prusa-slicer
    saleae-logic
    saleae-logic-2
    nixgl.nixGLIntel
  ];

  fonts.fontconfig.enable = true;

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  home.sessionVariables = {
    EDITOR = "hx";
  };

  programs.home-manager.enable = true;
}
