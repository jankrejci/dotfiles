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
        "dialout"
      ];
      # It's good practice to explicitly set the UID
      uid = 1000;
      hashedPassword = "$y$j9T$u.2s1lYSq.YKGJd0QN7cr.$rQlNj0kYmBpMqmFTK83GpMtYciDcryxABItQziWmml5";
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
