{ ... }:
{
  users.users = {
    paja = {
      isNormalUser = true;
      extraGroups = [
        "cups"
        "scanner"
        "lp"
        "networkmanager"
        "paja"
      ];
      uid = 5000;
      hashedPassword = "$y$j9T$osBbtqLvq0nOsFx1WThF40$oqcK0hbg8rgeLkX/ptVY5WJ32XTiRcuXkOT9DFMJ/i2";
    };
  };

  users.groups = {
    paja = {
      gid = 5000;
    };
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users = {
      paja = { ... }: {
        imports = [ ./home.nix ];
      };
    };
  };
}
