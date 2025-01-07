# users.nix
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

# Set passwords:
#sudo passwd <username>

# Manual set userid and groupid
#sudo usermod -u 5000 paja
#sudo groupmod -g 5000 paja
