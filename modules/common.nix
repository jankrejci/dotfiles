{
  config,
  lib,
  pkgs,
  ...
}: {
  nix.settings.experimental-features = ["nix-command" "flakes"];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  system.switch = {
    enable = false;
    enableNg = true;
  };

  # Consider users with the root access trustfull enough
  # to allow changes in the nix store
  nix.settings.trusted-users = ["@wheel"];

  # Since all ssh keys are password protected, allow users
  # to run sudo without password, which is convenient
  # option for the remote deployment
  security.sudo.wheelNeedsPassword = false;

  boot = {
    kernelModules = lib.mkDefault ["kvm-intel"];
    extraModulePackages = [];
    # Use tmpfs for /tmp (RAM-based, fast, auto-cleanup on reboot)
    tmp.useTmpfs = true;
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
      # Add modules to decrypt disk on boot
      kernelModules = [
        "ext4"
        "dm-snapshot"
        "dm-mod"
        "dm-cache"
        "dm-cache-smq"
      ];
    };
  };

  # Redirect nix builds to /var/tmp (disk) to avoid filling RAM
  systemd.services.nix-daemon = {
    environment.TMPDIR = "/var/tmp";
  };

  # Enable periodic SSD trim for performance and longevity
  services.fstrim.enable = true;

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
    sbctl
    gcc
    gnumake
  ];

  services.prometheus.exporters.node = {
    enable = true;
    # Listen on all interfaces, security enforced via firewall
    openFirewall = false;
    listenAddress = "0.0.0.0";
  };

  # Allow node exporter on Netbird interface only
  networking.firewall.interfaces."nb-homelab".allowedTCPPorts = [9100];

  # Nginx proxy for node-exporter (VPN-only HTTPS access)
  services.nginx.virtualHosts."grafana.krejci.io" = lib.mkIf config.services.nginx.enable {
    locations."/node-exporter/" = {
      proxyPass = "http://localhost:9100/";
      recommendedProxySettings = true;
      # Only allow access from Netbird VPN network
      extraConfig = ''
        allow 100.76.0.0/16;
        deny all;
      '';
    };
  };

  systemd.services.prometheus-node-exporter.serviceConfig = {
    Restart = "always";
    RestartSec = 5;
  };

  # Common directory for storing root secrets
  systemd.tmpfiles.rules = [
    "d /root/secrets 0700 root root -"
  ];

  system.stateVersion = "24.11"; # Did you read the comment?
}
