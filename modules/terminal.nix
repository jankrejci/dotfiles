{ pkgs, ... }:
{
  home.packages = with pkgs; [
    nerd-fonts.dejavu-sans-mono
    git-absorb # absorb git hunks within existing commits
    gitui # terminal-ui for git
  ];

  programs.alacritty = {
    enable = true;
    package = pkgs.alacritty;
    settings = {
      font.normal.family = "DejaVuSansMono";
      window = {
        decorations = "None";
        startup_mode = "Maximized";
      };
    };
  };

  xdg.desktopEntries."Alacritty" = {
    name = "Alacritty";
    comment = "Terminal emulator";
    icon = "Alacritty";
    exec = "alacritty";
    categories = [ "TerminalEmulator" ];
    terminal = false;
    mimeType = [ "text/plain" ];
  };

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

  programs.zellij = {
    enable = true;
    package = pkgs.unstable.zellij;
  };
  home.file.".config/zellij/config.kdl".text = ''
    keybinds {
        pane {
          bind "_" { NewPane "Down"; SwitchToMode "Normal"; }
          bind "|" { NewPane "Right"; SwitchToMode "Normal"; }
          bind "r" { SwitchToMode "RenamePane"; PaneNameInput 0;}
        }
        tab {
          bind "Ctrl t" { SwitchToMode "Normal"; }
        }
    }
    default_shell "nu"
    theme "nord"
    default_layout "compact"
    scrollback_editor "hx"
  '';

  xdg.desktopEntries."Zellij" = {
    name = "Zellij";
    comment = "Terminal multiplexer";
    exec = "alacritty -e zellij -l welcome";
    icon = "/home/jkr/dotfiles/modules/zellij/logo.png";
    categories = [ "System" "TerminalEmulator" ];
    terminal = false;
  };

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

  programs.starship = {
    enable = true;
    enableNushellIntegration = true;
    enableBashIntegration = true;
    settings = {
      c = {
        symbol = " ";
      };
      directory = {
        truncation_length = 1;
        read_only = "🔒";
      };
      git_branch = {
        symbol = " ";
      };
      os.symbols = {
        NixOS = "❄️ ";
        Arch = " ";
        Debian = " ";
        Linux = " ";
        Macos = " ";
        Raspbian = " ";
        Ubuntu = " ";
        Unknown = " ";
        Windows = "🪟 ";
      };
      package = {
        symbol = "📦 ";
        disabled = true;
      };
      python = {
        symbol = " ";
      };
      rust = {
        symbol = " ";
        format = "[ $version](red bold)";
      };
    };
  };

  programs.broot = {
    enable = true;
    package = pkgs.unstable.broot;
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

