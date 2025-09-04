{pkgs, ...}: {
  imports = [
    ./probe-rs.nix # udev rules for the probe-rs
  ];

  # Enable cross compilation support. It is needed to build aarch64 images.
  boot.binfmt.emulatedSystems = ["aarch64-linux"];

  services.xserver = {
    # Enable the X11 windowing system.
    enable = true;
    # Enable the GNOME Desktop Environment.
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;
    # Configure keymap in X11
    xkb = {
      layout = "us";
    };
  };

  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  # Enable CUPS to print documents.
  services.printing = {
    enable = true;
    drivers = with pkgs; [
      cnijfilter_4_00
      gutenprint
      cups-bjnp
    ];
  };

  # Enable scanning support
  hardware.sane = {
    enable = true;
    extraBackends = with pkgs; [sane-airscan];
    netConf = "192.168.0.136";
  };

  systemd.tmpfiles.rules = [
    "L+ /etc/sane-config/pixma.conf - - - - /dev/null"
    "w /etc/sane-config/pixma.conf - - - - bjnp://192.168.0.136"
  ];

  # Enable Avahi for network device discovery
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  networking.networkmanager.enable = true;
  security.rtkit.enable = true;
  services = {
    pulseaudio.enable = false;
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };
  };

  # Install firefox.
  programs.firefox.enable = true;

  # TODO make the hyprland usable
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  environment.systemPackages = with pkgs; [
    unstable.zellij
    unstable.helix
    unstable.nushell
    unstable.broot
    alacritty
    home-manager
    starship
    hexyl # hex viewer
    tealdeer # tldr help tool
    rclone
    cups
    vlc
    solaar
    rofi
    rofi-wayland
    eww
    powertop
    tlp
    brightnessctl
    age
    ssh-to-age
    neofetch
    git
    chromium
    sane-backends
    sane-frontends
    simple-scan
    avahi
    probe-rs-tools
  ];

  fonts.packages = with pkgs; [
    nerd-fonts.dejavu-sans-mono
  ];

  services.xserver.videoDrivers = ["modesetting"];
}
