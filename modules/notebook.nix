# Laptop hardware configuration
#
# - firmware updates via fwupd
# - thermald and powertop autotuning
# - bluetooth and fingerprint reader
# - disables USB autosuspend for HID devices
{pkgs, ...}: {
  # Device driver packages
  hardware.firmware = with pkgs; [
    linux-firmware
  ];

  # For better hardware compatibility
  hardware.enableAllFirmware = true;
  # Enable non-free firmware
  hardware.enableRedistributableFirmware = true;

  # Allow applications to update firmware
  services.fwupd.enable = true;

  # Secure boot here runs on locally enrolled sbctl keys with no shim on the
  # ESP, so fwupd finds no chainloadable helper and refuses every capsule
  # update. Accept the plain binary instead, which sign-bootloader signs with
  # the same key as the kernels.
  services.fwupd.uefiCapsuleSettings.DisableShimForSecureBoot = true;

  # Enable hardware accelerated graphic drivers
  hardware.graphics.enable = true;

  # Enable temperature management daemon
  services.thermald.enable = true;
  # Enable powertop autotuning (complements power-profiles-daemon)
  powerManagement.powertop.enable = true;

  # powertop autotuning runs after multi-user.target and re-enables WiFi
  # power save, and the mac80211 default is on regardless. Force it off once
  # after powertop so the boot state is deterministic. The udev rule below
  # re-asserts it on later interface events such as resume and reconnect.
  systemd.services.disable-wifi-powersave = {
    description = "Disable WiFi power save on MT7922";
    after = ["powertop.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for dev in /sys/class/net/wlan*; do
        [ -e "$dev" ] || continue
        ${pkgs.iw}/bin/iw dev "$(basename "$dev")" set power_save off
      done
    '';
  };

  # Bluetooth enabled for GNOME built-in support and Hyprland via blueman
  hardware.bluetooth.enable = true;

  # Enable fingerprint reader (if available on your model)
  services.fprintd.enable = true;

  # Disable autosuspend of selected USB peripherals
  services.udev.extraRules = ''
    # Disable autosuspend for mouse devices
    ACTION=="add", SUBSYSTEM=="usb", ATTR{product}=="*[Mm]ouse*", ATTR{power/autosuspend}="-1"
    # Disable autosuspend for keyboard devices
    ACTION=="add", SUBSYSTEM=="usb", ATTR{product}=="*[Kk]eyboard*", ATTR{power/autosuspend}="-1"
    # Disable autosuspend for Logitech Unifying Receivers (wireless mice/keyboards)
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="046d", ATTR{idProduct}=="c52b", ATTR{power/autosuspend}="-1"
    # Disable autosuspend for USB Receiver devices (generic wireless receivers)
    ACTION=="add", SUBSYSTEM=="usb", ATTR{product}=="*[Rr]eceiver*", ATTR{power/autosuspend}="-1"
    # powertop autotuning above enables WiFi power save, which makes the MT7922
    # mt7921e card miss beacons and deauth by local choice at full signal.
    # Re-assert power save off on interface add and every state change.
    ACTION=="add|change", SUBSYSTEM=="net", KERNEL=="wlan*", RUN+="${pkgs.iw}/bin/iw dev $name set power_save off"
  '';
}
