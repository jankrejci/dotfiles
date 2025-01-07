{ ... }:

{
  users.users = {
    jkr = {
      isNormalUser = true;
      extraGroups = [ "plugdev" "wheel" "cups" "networkmanager" "jkr" ];
      # It's good practice to explicitly set the UID
      uid = 1000;
    };
  };

  users.groups = {
    jkr = {
      gid = 1000;
    };
  };
}

# Set passwords:
#sudo passwd <username>

# Manual set userid and groupid
#sudo usermod -u 5000 paja
#sudo groupmod -g 5000 paja
