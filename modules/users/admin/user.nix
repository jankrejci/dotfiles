{ ... }:
{
  users.users = {
    admin = {
      isNormalUser = true;
      extraGroups = [ "plugdev" "wheel" "networkmanager" "admin" ];
      uid = 1001;
      hashedPassword = "$y$j9T$8qLqeoP/jNv9rFtFfyljl1$S/GqBaFaaCIluY88qW9app4APK49d9wFI.5CmfFnwH/";
    };
  };

  users.groups = {
    admin = {
      gid = 1001;
    };
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users = {
      admin = { ... }: {
        imports = [ ./home.nix ];
      };
    };
  };
}
