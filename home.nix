let
  secrets = import ./secrets.nix;
in

{ pkgs, ... }:

{
  home.username = (secrets.username);
  home.homeDirectory = (secrets.homeDirectory);

  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.11";

  imports = [
    ./apps/alacritty.nix # accelerated terminal emulator
    ./apps/starship.nix # customizable prompt
    ./apps/git.nix # the git
    ./apps/helix.nix # modal editor
    ./apps/zellij.nix # terminal multiplexer
    ./apps/nushell.nix # new type of shell
    ./apps/firefox.nix # web browser
  ];

  nixpkgs.config.allowUnfree = true;
  home.packages = with pkgs; [
    hexyl # cli hex viewer
    bat # cat clone with wings
    eza # ls replacement
    fd # find relplacement
    fzf # cli fuzzy finder
    zoxide # smarter cd command
    marksman # markdown LSP server
    gitui # terminal-ui for git
    tokei # code statistics tool
    ripgrep # search tool 
    tealdeer # tldr help tool
    shell_gpt # cli gpt prompt
    nil # nix LSP server
    rustup # rust install tool
    delta # syntax highlighting diff
    taplo # toml toolkit
    shfmt # bash file formatter
    nixpkgs-fmt # nix file formatter
    nu_scripts # handy scripts for nushell
    nodePackages.bash-language-server # bash LSP server
    python311Packages.python-lsp-server # python LSP server
    powerline-fonts # patched fonts used for zellij
    (pkgs.nerdfonts.override { fonts = [ "DejaVuSansMono" ]; }) # iconic fonts
    prusa-slicer # slicer for 3D printing
    saleae-logic # logic analyzer software old-version
    saleae-logic-2 # logic analyzer software
    nixgl.nixGLIntel # opengl wrapper for non-nixos distro
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
