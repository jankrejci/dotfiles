{ ... }:

{
  users.users = {
    paja = {
      isNormalUser = true;
      extraGroups = [ "cups" "networkmanager" "paja" ];
      uid = 5000;
    };
  };

  users.groups = {
    paja = {
      gid = 5000;
    };
  };
}
