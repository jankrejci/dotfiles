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
}
