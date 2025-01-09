{ ... }:

{
  users.users = {
    admin = {
      isNormalUser = true;
      extraGroups = [ "plugdev" "wheel" "networkmanager" "admin" ];
      uid = 1001;
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

  users.users.jkr.isNormalUser = true;
  # users.users.jkr.group = "jkr";
  # users.groups.jkr = { };
}
