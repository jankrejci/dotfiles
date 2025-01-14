{ ... }:
{
  users.users = {
    jkr = {
      isNormalUser = true;
      extraGroups = [
        "plugdev"
        "wheel"
        "cups"
        "networkmanager"
        "jkr"
      ];
      # It's good practice to explicitly set the UID
      uid = 1000;
    };
  };

  users.groups = {
    jkr = {
      gid = 1000;
    };
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users = {
      jkr = { ... }: {
        imports = [ ./home.nix ];
      };
    };
  };
}
