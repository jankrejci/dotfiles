{
  config,
  lib,
  pkgs,
  ...
}: let
  services = config.serviceConfig;
in {
  nix.settings.experimental-features = ["nix-command" "flakes"];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

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

  # Common system packages - minimal set for all hosts including RPi
  # Server-specific tools are in headless.nix, desktop tools in desktop.nix
  environment.systemPackages = with pkgs; [
    bash
    bash-completion
    coreutils
    curl
    jq
    pciutils
    rsync
    unzip
    usbutils
    vim
    wget
    bat # cat clone with wings
    eza # ls replacement
    fd # find replacement
    fzf # cli fuzzy finder
    zoxide # smarter cd command
    ripgrep # search tool
    htop # interactive process viewer
    dig # DNS lookup utility
    tcpdump
  ];

  services.prometheus.exporters.node = {
    enable = true;
    openFirewall = false;
    listenAddress = "127.0.0.1";
  };

  systemd.services.prometheus-node-exporter.serviceConfig = {
    Restart = "always";
    RestartSec = 5;
  };

  # Node exporter metrics via unified metrics proxy
  services.nginx.virtualHosts."metrics".locations."/metrics/node" = {
    proxyPass = "http://127.0.0.1:9100/metrics";
  };

  # Common directory for storing root secrets
  systemd.tmpfiles.rules = [
    "d /root/secrets 0700 root root -"
  ];

  # Shell aliases for all users (bash)
  environment.shellAliases = {
    sc = "systemctl";
    ssc = "sudo systemctl";
    jc = "journalctl";
  };

  # Enable bash completion
  programs.bash.completion.enable = true;

  # Completion for aliases - source completions and register for aliases
  programs.bash.interactiveShellInit = ''
    source /run/current-system/sw/share/bash-completion/completions/systemctl
    source /run/current-system/sw/share/bash-completion/completions/journalctl
    complete -F _systemctl sc ssc
    complete -F _journalctl jc
  '';

  system.stateVersion = "24.11"; # Did you read the comment?
}
