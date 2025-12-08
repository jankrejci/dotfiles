{
  lib,
  pkgs,
  modulesPath,
  cachedPkgs-aarch64 ? null,
  ...
}: {
  # Disable base.nix profile imported by sd-image module.
  # It adds recovery tools like w3m, testdisk, ddrescue that aren't needed on deployed RPi.
  disabledModules = ["${modulesPath}/profiles/base.nix"];

  # Board-specific base module (raspberry-pi-02, raspberry-pi-4, etc.)
  # is imported in each host's config file (hosts/prusa.nix, hosts/rpi4.nix)

  # Binary cache for nixos-raspberrypi flake
  nix.settings = {
    substituters = ["https://nixos-raspberrypi.cachix.org"];
    trusted-public-keys = ["nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="];
  };

  # Overlays for RPi builds:
  # 1. ffmpeg: Use RPi-optimized headless variant from nixos-raspberrypi cache.
  # 2. python3: Source from standard nixpkgs to hit cache.nixos.org.
  # 3. u-boot: Disable boot delay to skip keyboard wait during boot.
  #
  # nixos-raspberrypi uses nvmd/nixpkgs fork that doesn't match cache.nixos.org.
  # By overlaying from standard nixpkgs, derivation hashes match the cache.
  nixpkgs.overlays =
    [
      (final: prev: {
        ffmpeg = final.rpi.ffmpeg-headless;
      })
      # Disable U-Boot keyboard input wait during boot.
      # Default bootdelay=2 waits for keypress which delays boot and can hang
      # on headless systems. -2 skips autoboot delay entirely.
      (final: prev: {
        ubootRaspberryPi_64bit = prev.ubootRaspberryPi_64bit.override {
          extraConfig = ''
            CONFIG_BOOTDELAY=-2
          '';
        };
      })
    ]
    ++ lib.optionals (cachedPkgs-aarch64 != null) [
      (final: prev: {
        python3 = cachedPkgs-aarch64.python3;
        python3Packages = cachedPkgs-aarch64.python3Packages;
        # Don't overlay octoprint so it uses our ffmpeg-headless overlay.
      })
    ];

  # Add password for the admin user to be able to log in from local console
  users.users.admin.hashedPassword = "$y$j9T$8qLqeoP/jNv9rFtFfyljl1$S/GqBaFaaCIluY88qW9app4APK49d9wFI.5CmfFnwH/";

  # Raspberry Pi utilities (vcgencmd for temperature, throttling, etc.)
  # With raspberry-pi-nix, vcgencmd works because the RPi kernel has vcio driver
  environment.systemPackages = [pkgs.libraspberrypi];

  # Allow video group to access VideoCore interface
  services.udev.extraRules = ''
    KERNEL=="vchiq", GROUP="video", MODE="0660"
    KERNEL=="vcio", GROUP="video", MODE="0660"
  '';

  # Define proper wifi channels
  boot.extraModprobeConfig = lib.mkDefault ''
    options cfg80211 ieee80211_regdom=CZ
  '';

  # Disable unnecessary filesystems.
  # RPi only needs ext4 for root and vfat for boot firmware.
  boot.supportedFilesystems = lib.mkForce {
    ext4 = true;
    vfat = true;
  };
  boot.initrd.supportedFilesystems = lib.mkForce {
    ext4 = true;
    vfat = true;
  };

  # Disable wpa_supplicant since we use iwd from modules/networking.nix
  networking.wireless.enable = lib.mkForce false;

  # Root filesystem on SD card
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };

  # Use zram for compressed swap in RAM (beneficial for memory-constrained devices)
  zramSwap = {
    enable = true;
    algorithm = "zstd";
  };

  # TODO find out more unused services to disable
  # Disable unneeded features
  services = {
    avahi.enable = false;
    nfs.server.enable = false;
    samba.enable = false;
    journald.extraConfig = "Storage=volatile";
  };

  # TODO Turn off BT properly, it still emmits some errors
  # I dont need the bluetooth so far
  hardware.bluetooth.enable = false;

  # Disable documentation since RPi is deployed remotely.
  documentation = {
    enable = false;
    man.enable = false;
    doc.enable = false;
    info.enable = false;
    nixos.enable = false;
  };

  # Disable nix daemon since RPi is deployed via deploy-rs, not local rebuilds.
  nix.enable = false;

  # Override default packages to keep only rsync for file transfers.
  environment.defaultPackages = lib.mkForce [pkgs.rsync];

  # Disable fail2ban since RPi is not a critical endpoint and is behind VPN.
  services.fail2ban.enable = lib.mkForce false;

  # Disable full linux-firmware since RPi only needs wireless firmware.
  # The nixos-raspberrypi module sets enableRedistributableFirmware = true which pulls
  # in firmware for Intel, AMD, Nvidia etc that we don't need.
  hardware.enableRedistributableFirmware = lib.mkForce false;

  # Add only the firmware needed for RPi WiFi.
  hardware.firmware = [pkgs.raspberrypiWirelessFirmware];

  # Disable installer tools since config changes are deployed remotely via deploy-rs.
  system.disableInstallerTools = true;
}
