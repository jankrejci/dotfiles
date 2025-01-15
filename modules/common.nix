{ pkgs, ... }:
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  time.timeZone = "Europe/Prague";

  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "cs_CZ.UTF-8";
    LC_IDENTIFICATION = "cs_CZ.UTF-8";
    LC_MEASUREMENT = "cs_CZ.UTF-8";
    LC_MONETARY = "cs_CZ.UTF-8";
    LC_NAME = "cs_CZ.UTF-8";
    LC_NUMERIC = "cs_CZ.UTF-8";
    LC_PAPER = "cs_CZ.UTF-8";
    LC_TELEPHONE = "cs_CZ.UTF-8";
    LC_TIME = "cs_CZ.UTF-8";
  };

  console.keyMap = "us";

  # Common system packages
  environment.systemPackages = with pkgs; [
    unstable.zellij
    unstable.helix
    unstable.nushell
    unstable.broot
    starship
    curl
    bash
    home-manager
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
    nmap # network mapper
    htop # interactive process viewer 
    wireguard-tools
    dig # DNS lookup utility
    hexyl # hex viewer
  ];

  fonts.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "DejaVuSansMono" ]; })
  ];
}
