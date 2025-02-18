{ pkgs, ... }:
{
  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  networking.networkmanager.enable = true;

  # Enable cross compilation support. It is needed to build aarch64 images.
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
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
  hardware.sane.enable = true;

  # Install firefox.
  programs.firefox.enable = true;

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  environment.systemPackages = with pkgs; [
    unstable.alacritty
    cups
    vlc
    solaar
    rofi
    rofi-wayland
    eww
    powertop
    tlp
  ];

  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Enable support for display link devices
  nixpkgs.config.displaylink = {
    enable = true;
    # Use a fixed path relative to the repository
    driverFile = ./displaylink/displaylink-600.zip;
    # Provide a fixed hash that you'll get after downloading the file
    # Add the hash here after downloading and running nix-prefetch-url file://$(pwd)/modules/displaylink/displaylink-600.zip
    sha256 = "1ixrklwk67w25cy77n7l0pq6j9i4bp4lkdr30kp1jsmyz8daaypw";
  };

  # Add DisplayLink to video drivers
  services.xserver.videoDrivers = [ "displaylink" "modesetting" ];
}
