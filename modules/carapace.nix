{ pkgs, ... }:
{
  programs.carapace = {
    enable = true;
    package = pkgs.carapace.unstable;
    enableBashIntegration = true;
    enableNushellIntegration = true;
  };
}
