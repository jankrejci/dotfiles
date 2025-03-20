{ config, lib, pkgs, ... }:
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  boot = {
    kernelModules = lib.mkDefault [ "kvm-intel" ];
    extraModulePackages = [ ];
    initrd = {
      availableKernelModules = [
        "nvme"
        "thunderbolt"
        "ahci"
        "ehci_pci"
        "sdhci_pci"
        "xhci_pci"
        "usbhid"
        "usb_storage"
        "sd_mod"
      ];
      kernelModules = [ ];
    };
  };

  time.timeZone = "Europe/Prague";
  console.keyMap = "us";

  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
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
  };

  # Common system packages
  environment.systemPackages = with pkgs; [
    curl
    bash
    unzip
    wget
    coreutils
    rsync
    jq
    vim
    usbutils
    pciutils
    lshw
    bat # cat clone with wings
    eza # ls replacement
    fd # find relplacement
    fzf # cli fuzzy finder
    zoxide # smarter cd command
    ripgrep # search tool 
    nmap # network mapper
    htop # interactive process viewer 
    wireguard-tools
    dig # DNS lookup utility
    sops
    tcpdump
    nix-tree
    gitMinimal
  ];

  services.prometheus.exporters.node = {
    enable = true;
    openFirewall = true;
    listenAddress = config.hosts.self.ipAddress;
  };

  systemd.services.prometheus-node-exporter.serviceConfig = {
    Restart = "always";
    RestartSec = 5;
  };

  system.stateVersion = "24.11"; # Did you read the comment?
}
