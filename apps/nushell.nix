{ pkgs, ... }:

{
  programs.nushell = {
    enable = true;
    configFile.source = ./nushell/config.nu;
    envFile.source = ./nushell/env.nu;
    shellAliases = {
      ll = "ls -l";
      lt = "exa -T -L2";
      g = "git";
      cd = "z";
    };

    # extraConfig = ''
    #   source ${pkgs.nu_scripts}/share/nu_scripts/custom-completions/git/git-completions.nu
    #   source ${pkgs.nu_scripts}/share/nu_scripts/custom-completions/cargo/cargo-completions.nu
    #   source ${pkgs.nu_scripts}/share/nu_scripts/custom-completions/zellij/zellij-completions.nu
    # '';
  };
}
