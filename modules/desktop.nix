{
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./probe-rs.nix # udev rules for the probe-rs
  ];

  # Enable cross compilation support. It is needed to build aarch64 images.
  boot.binfmt.emulatedSystems = ["aarch64-linux"];

  # Plymouth boot splash configuration
  # Requirements:
  # - boot.initrd.systemd.enable = true (set in disk-tpm-encryption.nix)
  # - boot.initrd.kernelModules = ["amdgpu"] (set in hosts/framework.nix)
  #
  # Press Space/ESC during splash to show boot menu
  #
  # Troubleshooting:
  # - plymouth --ping                          # check if running
  # - sudo journalctl -b -u plymouth-start.service
  # - sudo journalctl -b | grep -i plymouth
  # - sudo dmesg | grep -i drm                 # check graphics init
  boot = {
    consoleLogLevel = 0;
    initrd.verbose = false;
    kernelParams = [
      "quiet"
      # Suppress all kernel messages except emergencies (0=emergency only)
      "loglevel=0"
      "boot.shell_on_fail"
      "splash"
      # Hide systemd status messages for flicker-free boot
      "rd.systemd.show_status=false"
      "systemd.show_status=false"
      "rd.udev.log_level=3"
      "udev.log_level=3"
      # Disable cursor blink on console
      "vt.global_cursor_default=0"
      # Skip simpledrm, use native amdgpu directly (avoids driver handoff delay)
      "plymouth.use-simpledrm=0"
      # Debug logging (uncomment for troubleshooting)
      # "plymouth.debug"
    ];
    plymouth = {
      enable = true;
      # Requires amdgpu in initrd.kernelModules (see hosts/framework.nix)
      theme = "bgrt";
    };
    # Hide boot menu by default (press Space/ESC to show)
    loader.timeout = lib.mkForce 0;
  };

  # Fix Plymouth keyboard input by setting XKB config path
  # NOTE: xkbcommon will still log an ERROR about the default path, but keyboard
  # input works correctly - the error is harmless (xkbcommon tries default first)
  systemd.services.plymouth-start.environment = {
    XKB_CONFIG_ROOT = "${pkgs.xkeyboard_config}/share/X11/xkb";
  };

  # Improve Plymouth to GDM handoff (reduce black screen with external monitors)
  systemd.services.display-manager = {
    # Remove plymouth-quit from conflicts so Plymouth stays visible during handoff
    # NOTE: Cannot use after/wants with plymouth-quit-wait - creates circular dependency
    # (plymouth-quit-wait waits for boot completion, which requires display-manager)
    conflicts = lib.mkForce ["shutdown.target" "getty@tty7.service"];
  };

  services.xserver = {
    # Enable the X11 windowing system.
    enable = true;
    # Configure keymap in X11
    xkb = {
      layout = "us";
    };
  };

  # Enable the GNOME Desktop Environment
  services.desktopManager.gnome.enable = true;

  # Display manager
  services.displayManager.gdm = {
    enable = true;
    # Keep Plymouth running until GDM is ready (smoother handoff)
    wayland = true;
  };

  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  services.flatpak = {
    enable = true;
    remotes = [
      {
        name = "flathub";
        location = "https://flathub.org/repo/flathub.flatpakrepo";
      }
      {
        name = "flathub-beta";
        location = "https://flathub.org/beta-repo/flathub-beta.flatpakrepo";
      }
    ];
    packages = [
      {
        appId = "org.freecad.FreeCAD";
        origin = "flathub-beta";
      }
      "app.zen_browser.zen"
      "org.mozilla.firefox"
      "org.kicad.KiCad"
      "org.ghidra_sre.Ghidra"
      "com.prusa3d.PrusaSlicer"
      "com.google.Chrome"
    ];
    update.onActivation = true;
  };

  # Enable CUPS to print documents.
  services.printing = {
    enable = true;
    browsed.enable = false;
    drivers = with pkgs; [
      cnijfilter_4_00
      gutenprint
      cups-bjnp
    ];
  };

  # Brother printer accessible via VPN. Uses IPP Everywhere, no driver needed.
  # Custom service because NixOS ensurePrinters stops cups which loses config.
  systemd.services.setup-printer = {
    description = "Configure Brother printer";
    wantedBy = ["multi-user.target"];
    after = ["cups.service" "network-online.target"];
    wants = ["network-online.target"];
    path = [pkgs.cups];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Skip if already configured
      lpstat -p Brother-DCP-T730DW &>/dev/null && exit 0

      # Add printer with IPP Everywhere
      lpadmin -p Brother-DCP-T730DW \
        -v ipps://brother.krejci.io:443/ipp/print \
        -m everywhere \
        -D "Brother DCP-T730DW" \
        -L "Home" \
        -E || true

      # Set as default
      lpadmin -d Brother-DCP-T730DW || true
    '';
  };

  # Enable scanning support
  hardware.sane = {
    enable = true;
    extraBackends = with pkgs; [sane-airscan];
  };

  # Brother scanner accessible via VPN, uses eSCL protocol
  environment.etc."sane.d/airscan.conf".text = ''
    [devices]
    "Brother DCP-T730DW" = https://brother.krejci.io:443/eSCL
  '';

  # Disable v4l backend so webcam doesn't appear as scanner
  environment.etc."sane.d/v4l.conf".text = "";

  # Disable escl backend, we use airscan instead
  environment.etc."sane.d/escl.conf".text = "";

  # Avahi disabled - causes random auto-appearing printers via CUPS dnssd backend
  # VPN printer is preconfigured, no need for mDNS discovery
  services.avahi.enable = false;

  networking.networkmanager = {
    enable = true;
    # OpenVPN plugin for GUI-configured VPN connections. Has GTK dependency.
    plugins = [pkgs.networkmanager-openvpn];
  };
  security.rtkit.enable = true;
  services = {
    # Use dbus-broker for better performance
    dbus.implementation = "broker";
    pulseaudio.enable = false;
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };
  };

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
    eww
    powertop
    tlp
    brightnessctl
    age
    agenix-rekey
    ssh-to-age
    neofetch
    git
    sane-backends
    sane-frontends
    simple-scan
    avahi
    probe-rs-tools
    # Tools also in headless.nix - desktops need them too
    nmap
    wireguard-tools
    nix-tree
    sbctl
    lshw
    # GNOME extensions installed system-wide, enabled per-user via dconf
    gnomeExtensions.appindicator
    gnomeExtensions.vitals
    gnomeExtensions.dash-to-panel
    unstable.gnomeExtensions.unite
    gnomeExtensions.notification-banner-reloaded
  ];

  # Required for AppIndicator tray icons
  services.udev.packages = [pkgs.gnome-settings-daemon];

  fonts.packages = with pkgs; [
    nerd-fonts.dejavu-sans-mono
  ];

  services.xserver.videoDrivers = ["modesetting"];
}
