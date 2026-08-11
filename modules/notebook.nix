# Laptop hardware configuration
#
# - firmware updates via fwupd, capsule helper signed for secure boot
# - thermald and powertop autotuning
# - bluetooth and fingerprint reader
# - disables USB autosuspend for HID devices
{
  config,
  pkgs,
  ...
}: let
  fwupdEfi = config.services.fwupd.package.fwupd-efi;
  inherit (fwupdEfi) signedApp;
in {
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

  # Secure boot here runs on locally enrolled sbctl keys, so there is no shim
  # to chainload the capsule helper with. fwupd still sources that helper from
  # the .signed path, which pkgs/fwupd-efi-signed.nix redirects into /var/lib
  # for the service below to fill in.
  services.fwupd.uefiCapsuleSettings.DisableShimForSecureBoot = true;

  systemd.tmpfiles.rules = ["d ${builtins.dirOf signedApp} 0755 root root -"];

  # The signature cannot live in the store, the sbctl key is machine local and
  # must stay that way. The unit signs at boot and re-signs whenever fwupd-efi
  # changes, via restartTriggers below, so a new helper is covered before the
  # daemon ever follows the symlink.
  #
  # Both the sbctl key and enroll-secure-boot-keys.service come from
  # modules/disk-tpm-encryption.nix. This module depends on that one without
  # importing it, which holds because every notebook host takes both. On a host
  # that took this module alone the unit would fail at the signing step, since
  # only Setup Mode is treated as nothing-to-sign-with.
  systemd.services.sign-fwupd-efi = {
    description = "Sign the fwupd EFI capsule helper for secure boot";
    wantedBy = ["multi-user.target"];
    before = ["fwupd.service"];
    after = ["enroll-secure-boot-keys.service"];
    path = with pkgs; [sbctl];
    restartTriggers = [fwupdEfi];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -euo pipefail

      # Nothing to sign with until the first boot enrolls the keys.
      status_output=$(sbctl status)
      if grep -qE "Setup Mode:.*Enabled" <<< "$status_output"; then
        echo "Setup Mode enabled, skipping capsule helper signing"
        exit 0
      fi

      sbctl sign -o ${signedApp} ${fwupdEfi}/libexec/fwupd/efi/fwupdx64.efi
      echo "Signed capsule helper to ${signedApp}"
    '';
  };

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
  #
  # Pulled in by powertop.service rather than multi-user.target: powertop is
  # itself ordered after multi-user.target, and a target implicitly waits for
  # what it wants, so hanging this unit off the target closes an ordering
  # cycle that systemd breaks by dropping this job from the boot transaction.
  systemd.services.disable-wifi-powersave = {
    description = "Disable WiFi power save";
    after = ["powertop.service"];
    wantedBy = ["powertop.service"];
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
    # Bluetooth radios sit on USB even when the wifi half of the same chip is on
    # PCIe. Suspending the radio and then failing to wake it takes the shared
    # die down with it: the wifi firmware reloads, the adapter re-enumerates
    # under a new hci index, and every connected device silently drops.
    # Class e0 is the wireless controller class, so this covers the radio
    # whatever the vendor calls its product string.
    ACTION=="add", SUBSYSTEM=="usb", ATTR{bDeviceClass}=="e0", ATTR{power/autosuspend}="-1"
    # powertop autotuning above enables WiFi power save, which makes the MT7922
    # mt7921e card miss beacons and deauth by local choice at full signal.
    # Re-assert power save off on interface add and every state change.
    ACTION=="add|change", SUBSYSTEM=="net", KERNEL=="wlan*", RUN+="${pkgs.iw}/bin/iw dev $name set power_save off"
  '';
}
