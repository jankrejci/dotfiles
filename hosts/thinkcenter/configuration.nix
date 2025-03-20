{ config, ... }:
{
  # Access to all raspberry hosts without sudo for convenience
  security.sudo.wheelNeedsPassword = false;

  # Add password for the admin user to be able to log in from local console
  users.users.admin.hashedPassword = "$y$j9T$8qLqeoP/jNv9rFtFfyljl1$S/GqBaFaaCIluY88qW9app4APK49d9wFI.5CmfFnwH/";

  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "jkr@optiplex:KwH9qv7qCHd+npxC0FUFCApM1rP6GSbB8Ze983CCT8o="
  ];

  hardware.cpu.intel.updateMicrocode = config.hardware.enableRedistributableFirmware;
}
