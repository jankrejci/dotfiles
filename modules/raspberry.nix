# Raspberry Pi base configuration
#
# - cachix binary cache for nixos-raspberrypi
# - board-specific u-boot from cache with custom env
# - uboot.env to disable autoboot prompt without recompiling u-boot
# - disables bluetooth for serial UART access
# - minimal packages and disabled services
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: let
  envSize = "0x4000";

  ubootPkg =
    {
      "02" = pkgs.ubootRaspberryPi3_64bit;
      "3" = pkgs.ubootRaspberryPi3_64bit;
      "4" = pkgs.ubootRaspberryPi4_64bit;
    }.${
      config.boot.loader.raspberry-pi.variant
    };

  # Build uboot.env from the stock u-boot binary's default environment
  # with bootdelay=-2. Serial-connected GPS modules send NMEA data that
  # triggers the "Hit any key" autoboot prompt and halts boot.
  # bootdelay=-2 skips the prompt entirely.
  #
  # CONFIG_ENV_IS_IN_FAT=y (Kconfig default for ARCH_BCM283X) makes u-boot
  # read uboot.env from the firmware FAT partition, replacing the entire
  # compiled-in default environment.
  #
  # Pipeline: strings (extract) -> mkenvimage (pack) -> fw_setenv (patch)
  # -> fw_printenv (verify). No u-boot recompilation needed.
  ubootEnv =
    pkgs.runCommand "uboot-env" {
      nativeBuildInputs = [pkgs.ubootTools pkgs.binutils];
    } ''
      strings ${ubootPkg}/u-boot.bin \
        | grep -E '^[a-zA-Z_][a-zA-Z0-9_]*=.' \
        > env.txt

      mkenvimage -s ${envSize} -o $out env.txt
      echo "$out 0x0000 ${envSize}" > fw_env.config
      fw_setenv -c fw_env.config -l $TMPDIR bootdelay -- -2
      fw_printenv -c fw_env.config -l $TMPDIR bootdelay | grep -q 'bootdelay=-2'
    '';
in {
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

  # Use stock board-specific u-boot from nixpkgs binary cache.
  # Autoboot prompt is disabled via uboot.env, not u-boot recompilation.
  boot.loader.raspberry-pi.ubootPackage = ubootPkg;

  # Install uboot.env to firmware partition on activation.
  # u-boot reads this from the FAT partition, replacing the compiled-in
  # default environment with our bootdelay=-2 version.
  system.activationScripts.ubootEnv.text = ''
    if [ -d /boot/firmware ]; then
      install -m 644 ${ubootEnv} /boot/firmware/uboot.env
    fi
  '';

  # Skip boot menu on headless systems. Default 5 second timeout is unnecessary
  # when there's only one generation and no keyboard attached.
  boot.loader.timeout = 0;

  # Raspberry Pi utilities (vcgencmd for temperature, throttling, etc.)
  # With raspberry-pi-nix, vcgencmd works because the RPi kernel has vcio driver
  # iw is for WiFi diagnostics and TX power adjustment
  environment.systemPackages = [pkgs.libraspberrypi pkgs.iw];

  # Allow video group to access VideoCore interface
  services.udev.extraRules = ''
    KERNEL=="vchiq", GROUP="video", MODE="0660"
    KERNEL=="vcio", GROUP="video", MODE="0660"
  '';

  # Define proper wifi channels
  boot.extraModprobeConfig = ''
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

  # Firmware partition for config.txt and bootloader. Uses automount to avoid
  # keeping FAT32 mounted unnecessarily. deploy-config updates this partition.
  fileSystems."/boot/firmware" = {
    device = "/dev/disk/by-label/FIRMWARE";
    fsType = "vfat";
    options = ["noatime" "noauto" "x-systemd.automount" "x-systemd.idle-timeout=1min"];
  };

  # Use file-based swap. Zram compresses RAM into itself which doesn't help
  # when actually out of memory. File swap on SD is slower but provides real
  # additional memory capacity.
  swapDevices = [
    {
      device = "/swapfile";
      size = 1024;
    }
  ];

  # Fix tmpfiles config that references non-existent 'sudo' group.
  # Use 'wheel' instead for debug filesystem access.
  systemd.tmpfiles.settings."10-kernel-debug"."/sys/kernel/debug".d = {
    mode = "0750";
    user = "root";
    group = "wheel";
  };

  # Disable unneeded features
  services = {
    avahi.enable = false;
    nfs.server.enable = false;
    samba.enable = false;
    journald.extraConfig = "Storage=volatile";
  };

  # Disable Bluetooth to free ttyAMA0 for serial devices like GPS, 3D printers.
  # On RPi4 this restores PL011 UART to GPIO 14/15 and creates /dev/ttyAMA0.
  hardware.bluetooth.enable = false;
  boot.blacklistedKernelModules = ["hci_uart"];

  # BCM2711 firmware bug: empty dtoverlay= lines cause preceding overlay to be
  # skipped. nixos-raspberrypi's dt-overlays adds dtoverlay= after each overlay
  # per RPi docs, but bcm2711 firmware mishandles this. bcm2837 works fine.
  # Workaround: disable dt-overlays mechanism and use extra-config directly.
  # See: vclog shows overlay not loaded despite correct config.txt syntax.
  hardware.raspberry-pi.config.all.dt-overlays.vc4-kms-v3d.enable = lib.mkForce false;
  hardware.raspberry-pi.extra-config = ''
    [all]
    dtoverlay=disable-bt
    dtoverlay=vc4-kms-v3d
    dtparam=i2c_arm=on
  '';

  # I2C for GPS configuration on RAK2245 and other HATs
  hardware.i2c.enable = true;

  # Disable documentation since RPi is deployed remotely.
  documentation = {
    enable = false;
    man.enable = false;
    doc.enable = false;
    info.enable = false;
    nixos.enable = false;
  };

  # Override default packages to keep only rsync for file transfers.
  # i2c-tools needed for GPS configuration on RAK2245
  environment.defaultPackages = lib.mkForce [pkgs.rsync pkgs.i2c-tools];

  # Disable fail2ban since RPi is not a critical endpoint and is behind VPN.
  services.fail2ban.enable = lib.mkForce false;

  # Disable full linux-firmware since RPi only needs wireless firmware.
  # The nixos-raspberrypi module sets enableRedistributableFirmware = true which pulls
  # in firmware for Intel, AMD, Nvidia etc that we don't need.
  hardware.enableRedistributableFirmware = lib.mkForce false;

  # Add only the firmware needed for RPi WiFi.
  hardware.firmware = with pkgs; [
    raspberrypiWirelessFirmware
    wireless-regdb
  ];

  # Disable installer tools since config changes are deployed remotely via deploy-rs.
  system.disableInstallerTools = true;
}
