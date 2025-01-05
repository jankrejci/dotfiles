{ pkgs, ... }:

{
  # Server-side SSH configuration
  services.openssh = {
    enable = true;

    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };
}
