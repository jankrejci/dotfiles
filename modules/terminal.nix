# Terminal environment for home-manager
#
# - nushell shell with vi mode
# - git with delta diff viewer
# - starship prompt with nerd fonts
# - zoxide, broot, carapace completions
{pkgs, ...}: {
  home.packages = with pkgs; [
    nerd-fonts.dejavu-sans-mono
    git-absorb # absorb git hunks within existing commits
    tig # terminal-ui for git
  ];

  programs.nushell = {
    enable = true;
    package = pkgs.unstable.nushell;
    extraConfig = ''
      $env.config = {
        completions: {
          algorithm: 'fuzzy',
        },
        history: {
          file_format: 'sqlite',
          sync_on_enter: true,
          isolation: true,
        },
        show_banner: false,
        keybindings: [
          {
            name: open_editor
            modifier: control
            keycode: char_e
            mode: [vi_normal vi_insert emacs]
            event: { send: OpenEditor}
          }
        ]
      }
    '';

    extraEnv = ''
      $env.EDITOR = "hx"
      $env.config.edit_mode = "vi"
      $env.PROMPT_INDICATOR_VI_NORMAL = $"(ansi bg_blue)(ansi black_bold) NOR (ansi reset) "
      $env.PROMPT_INDICATOR_VI_INSERT = $"(ansi bg_green)(ansi black_bold) INS (ansi reset) "
    '';

    shellAliases = {
      ll = "ls -l";
      le = "eza --git-ignore -l -sName --group-directories-first";
      lt = "le -T";
      g = "git";
      cd = "z";
      sc = "systemctl";
      ssc = "sudo systemctl";
      jc = "journalctl";
    };
  };

  programs.git = {
    enable = true;
    settings = {
      core.editor = "hx";
      alias = {
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
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      dark = true;
    };
  };

  programs.starship = {
    enable = true;
    enableNushellIntegration = true;
    enableBashIntegration = true;
    settings = {
      c = {
        symbol = " ";
      };
      directory = {
        truncation_length = 1;
        read_only = " ";
      };
      git_branch = {
        symbol = " ";
      };
      os.symbols = {
        NixOS = "󱄅";
        Arch = " ";
        Debian = " ";
        Linux = " ";
        Macos = " ";
        Raspbian = " ";
        Ubuntu = " ";
        Unknown = " ";
        Windows = " ";
      };
      package = {
        symbol = " ";
        disabled = true;
      };
      python = {
        symbol = " ";
      };
      rust = {
        symbol = " ";
        format = "[ $version](red bold)";
      };
    };
  };

  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
    enableNushellIntegration = true;
  };

  programs.broot = {
    enable = true;
    package = pkgs.unstable.broot;
    enableBashIntegration = true;
    enableNushellIntegration = true;
    settings = {
      icon_theme = "nerdfont";
    };
  };

  programs.carapace = {
    enable = true;
    package = pkgs.unstable.carapace;
    enableBashIntegration = true;
    enableNushellIntegration = true;
  };
}
