{
  lib,
  pkgs,
  ...
}: {
  # Add password for the admin user to be able to log in from local console
  users.users.admin.hashedPassword = "$y$j9T$8qLqeoP/jNv9rFtFfyljl1$S/GqBaFaaCIluY88qW9app4APK49d9wFI.5CmfFnwH/";

  # Allow nixos-anywhere to login as root for installation
  services.openssh.settings.PermitRootLogin = lib.mkForce "yes";

  # Avoid UCSI complains on framework laptop
  boot.kernelParams = ["ucsi.ignore_altmode=1" "ucsi.debug=1" "typec.blacklist=1"];

  systemd.services.disable-ucsi = {
    description = "Disable UCSI kernel module";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.kmod}/bin/rmmod ucsi_acpi";
      RemainAfterExit = true;
    };
  };
}
