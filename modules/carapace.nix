{ pkgs, ... }:
{
  # TODO merge those small snippets into single module
  programs.carapace = {
    enable = true;
    package = pkgs.unstable.carapace;
    enableBashIntegration = true;
    enableNushellIntegration = true;
  };
}
