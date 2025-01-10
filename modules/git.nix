{ pkgs, ... }:

{
  programs.git = {
    enable = true;
    delta = {
      enable = true;
      options = {
        dark = true;
      };
    };
    extraConfig.core.editor = "hx";
    aliases = {
      ll = "log --pretty=format:'%Cred%h %Cgreen(%ad) %C(bold blue)<%an>%Creset %s %C(yellow)%d%Creset' --abbrev-commit --date=format:'%Y-%m-%d'";
      ri = "rebase --interactive";
      ria = "rebase --interactive --autosquash";
      riam = "rebase --interactive --autosquash origin/master";
      ra = "rebase --abort";
      rc = "rebase --continue";
      ap = "add -p";
      c = "commit";
      cfh = "commit --fixup=HEAD";
      fm = "!git fetch; git checkout origin/master";
      f = "fetch";
      st = "status";
      sh = "show";
      co = "checkout";
      cob = "checkout -b";
    };
  };
  home.packages = with pkgs; [
    git-absorb # absorb git hunks within existing commits
    gitui # terminal-ui for git
  ];
}
