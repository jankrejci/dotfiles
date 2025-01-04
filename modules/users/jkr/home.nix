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
    ../../hyprland.nix # tiling window manager
  ];

  nixpkgs.config.allowUnfree = true;
  home.packages = with pkgs; [
    rshell
    hexyl # cli hex viewer
    gitui # terminal-ui for git
    tokei # code statistics tool
    tealdeer # tldr help tool
    unstable.shell-gpt # cli gpt prompt
    unstable.nil # nix LSP server
    unstable.rustup # rust install tool
    git-absorb # absorb git hunks within existing commits
    delta # syntax highlighting diff
    taplo # toml toolkit
    unstable.espflash
    unstable.carapace # terminal command auto complete
    python311Packages.python-lsp-server # python LSP server
    powerline-fonts # patched fonts used for zellij
    (pkgs.nerdfonts.override { fonts = [ "DejaVuSansMono" ]; }) # iconic fonts
    unstable.prusa-slicer # slicer for 3D printing
    saleae-logic # logic analyzer software old-version
    saleae-logic-2 # logic analyzer software
    libarchive # contains bsdtar tool needed to install nvidia driver
    # nixgl.auto.nixGLDefault # opengl wrapper for non-nixos distro
    slint-lsp # slint LSP server, rust GUI framework
    gnomeExtensions.vitals
    gnomeExtensions.dash-to-panel
    kicad
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
}
