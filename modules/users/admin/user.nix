{ ... }:
{
  users.users = {
    admin = {
      isNormalUser = true;
      extraGroups = [ "plugdev" "wheel" "networkmanager" "admin" ];
      uid = 1001;
      hashedPassword = "$y$j9T$XAzdd2RQeVBlBssRJ33.B.$IiMIyCUpT14.TYNYgXN9Nl4.kEqG/48vhqEE7Us4BN6";
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
}
