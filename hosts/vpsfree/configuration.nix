{...}: {
  # Add password for the admin user to be able to log in from local console
  users.users.admin.hashedPassword = "$y$j9T$8qLqeoP/jNv9rFtFfyljl1$S/GqBaFaaCIluY88qW9app4APK49d9wFI.5CmfFnwH/";

  systemd.extraConfig = ''
    DefaultTimeoutStartSec=900s
  '';

  # Avoid collision between networking and vpsadminos module
  systemd.network.networks."98-all-ethernet".DHCP = "no";

  # There is no DHCP, so fixed dns is needed
  networking.nameservers = ["1.1.1.1" "8.8.8.8"];
}
