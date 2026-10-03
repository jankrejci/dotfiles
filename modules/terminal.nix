# Terminal environment for home-manager
#
# - nushell shell with vi mode
# - git with delta diff viewer
# - starship prompt with nerd fonts
# - zoxide, broot, carapace completions
{
  pkgs,
  config,
  ...
}: {
  home.packages = with pkgs; [
    nerd-fonts.dejavu-sans-mono
    git-absorb # absorb git hunks within existing commits
    tig # terminal-ui for git
    unstable.fzf # 0.74+ for the nushell integration generated below
  ];

  # fzf grew a nushell integration in 0.74, giving nushell the same ** trigger
  # and ctrl-t, ctrl-r and alt-c bindings the bash and zsh scripts always had.
  # Stable nixpkgs is still on 0.72, which has no --nushell, so the generator
  # and the binary on PATH both come from unstable to keep them in step.
  #
  # It goes in the autoload directory rather than extraConfig because the
  # completer wraps whichever external completer is already registered, and
  # carapace registers itself from config.nu. Autoload runs after config.nu,
  # so fzf handles the trigger and defers to carapace for everything else.
  home.file.".config/nushell/autoload/fzf.nu".source = pkgs.runCommand "fzf.nu" {} ''
    ${pkgs.unstable.fzf}/bin/fzf --nushell > $out
  '';
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
      sc = "systemctl";
      ssc = "sudo systemctl";
      jc = "journalctl";
    };
  };

  # Tig colors use ANSI names that map to Alacritty's base16 palette,
  # so a single config adapts to all theme variants automatically.
  home.file.".config/tig/config".text = ''
    # General UI
    color default       white   default
    color cursor        black   blue    bold
    color title-focus   black   blue    bold
    color title-blur    white   default
    color search-result black   yellow
    color delimiter     cyan    default
    color header        yellow  default bold
    color line-number   yellow  default
    color id            blue    default
    color date          cyan    default
    color author        green   default
    color mode          cyan    default
    color status        green   default

    # Main view
    color main-commit   default default
    color main-head     green   default bold
    color main-remote   red     default
    color main-tag      yellow  default bold
    color main-ref      cyan    default
    color graph-commit  blue    default

    # Diff
    color diff-header   yellow  default bold
    color diff-chunk    magenta default
    color diff-add      green   default
    color diff-del      red     default
    color diff-stat     blue    default

    # Status
    color stat-staged   green   default
    color stat-unstaged yellow  default
    color stat-untracked red    default
  '';

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

  # Delta dark/light is managed via a mutable include file so the theme
  # toggle can switch it at runtime without touching the HM-managed config.
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      line-numbers = true;
    };
  };

  programs.git.includes = [{path = "~/.config/git/delta-theme.gitconfig";}];

  home.file.".config/git/${config.colorScheme.themeName}-dark.gitconfig".text = ''
    [delta]
      dark = true
  '';
  home.file.".config/git/${config.colorScheme.themeName}-light.gitconfig".text = ''
    [delta]
      light = true
  '';

  theme.toggle = [
    {
      name = "delta";
      switch = pkgs.writeShellApplication {
        name = "theme-switch-delta";
        text = ''
          cat "${config.xdg.configHome}/git/${config.colorScheme.themeName}-$1.gitconfig" > "${config.xdg.configHome}/git/delta-theme.gitconfig"
        '';
      };
      seed = [
        {
          source = "${config.xdg.configHome}/git/${config.colorScheme.themeName}-\${mode}.gitconfig";
          target = "${config.xdg.configHome}/git/delta-theme.gitconfig";
        }
      ];
    }
  ];

  programs.starship = {
    enable = true;
    enableNushellIntegration = true;
    enableBashIntegration = true;
    settings = {
      # Starship uses ANSI color names that map to the terminal's palette.
      # Since alacritty swaps its color scheme at runtime, starship colors
      # adapt automatically without needing its own theme toggle.
      palette = "ansi";

      # $all puts $custom after every language module, far from $directory, so
      # the prefix is spelled out to slot the parent path in front of it. $all
      # still covers everything not named here and does not duplicate these.
      format = "$username$hostname$localip$shlvl$singularity$kubernetes$nats\${custom.path_parent}$directory$all";
      palettes.ansi = {
        red = "red";
        orange = "bright-red";
        yellow = "yellow";
        green = "green";
        cyan = "cyan";
        blue = "blue";
        purple = "purple";
        foreground = "white";
        background = "black";
        grey = "bright-black";
      };
      c = {
        symbol = " ";
      };
      # Starship styles $path as one unit, so the leaf cannot be coloured apart
      # from its parents by the directory module alone. The parent path is
      # emitted by a custom module in grey and directory then renders only the
      # final component in cyan, which is why truncation is pinned to one
      # segment and repo truncation is off.
      directory = {
        truncation_length = 1;
        truncate_to_repo = false;
        read_only = " ";
      };

      custom.path_parent = {
        description = "Parent directories of the working directory, dimmed";
        when = true;
        style = "grey";
        format = "[$output]($style)";
        shell = ["${pkgs.bash}/bin/bash" "--noprofile" "--norc"];
        command = ''
          p=''${PWD/#$HOME/\~}
          [ "$p" = / ] && exit 0
          d=''${p%/*}
          [ "$d" = "$p" ] && exit 0
          [ -z "$d" ] && exit 0
          printf '%s/' "$d"
        '';
      };
      git_branch = {
        symbol = " ";
      };
      os.symbols = {
        NixOS = "󱄅";
        Arch = " ";
        Debian = " ";
        Linux = " ";
        Macos = " ";
        Raspbian = " ";
        Ubuntu = " ";
        Unknown = " ";
        Windows = " ";
      };
      package = {
        symbol = " ";
        disabled = true;
      };
      python = {
        symbol = " ";
      };
      rust = {
        symbol = " ";
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
