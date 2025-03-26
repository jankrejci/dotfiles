{ config, ... }:
{
  # Access for all hosts without sudo for convenience
  security.sudo.wheelNeedsPassword = false;

  # Add password for the admin user to be able to log in from local console
  users.users.admin.hashedPassword = "$y$j9T$8qLqeoP/jNv9rFtFfyljl1$S/GqBaFaaCIluY88qW9app4APK49d9wFI.5CmfFnwH/";

  hardware.cpu.intel.updateMicrocode = config.hardware.enableRedistributableFirmware;
}
