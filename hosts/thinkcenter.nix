{lib, ...}: {
  # Add password for the admin user to be able to log in from local console
  users.users.admin.hashedPassword = "$y$j9T$8qLqeoP/jNv9rFtFfyljl1$S/GqBaFaaCIluY88qW9app4APK49d9wFI.5CmfFnwH/";

  hardware.cpu.intel.updateMicrocode = true;

  # Enable processes collector for detailed monitoring (systemd already enabled in common.nix)
  services.prometheus.exporters.node.enabledCollectors = lib.mkForce ["systemd" "processes"];
}
