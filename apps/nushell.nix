{ pkgs, ... }:

{
  programs.nushell = {
    enable = true;
    package = pkgs.unstable.nushell;
    configFile.source = ./nushell/config.nu;
    envFile.source = ./nushell/env.nu;
    shellAliases = {
      ll = "ls -l";
      lt = "exa -T -L2";
      g = "git";
      cd = "z";
    };
  };
}
