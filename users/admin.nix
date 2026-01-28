# Admin user for remote deployment
#
# - wheel and networkmanager groups
# - used by deploy-rs and nixos-anywhere
# - password managed by agenix
{config, ...}: {
  # Password hash for admin user
  age.secrets.admin-password-hash = {
    rekeyFile = ../secrets/admin-password-hash.age;
  };

  users.users = {
    admin = {
      isNormalUser = true;
      extraGroups = ["plugdev" "wheel" "networkmanager" "admin"];
      uid = 1001;
      hashedPasswordFile = config.age.secrets.admin-password-hash.path;
    };
  };

  users.groups = {
    admin = {
      gid = 1001;
    };
  };
}
