{ pkgs, ... }:

{
  home.packages = with pkgs; [
    ltex-ls # spell check language server
    nodePackages.bash-language-server # bash language server
    python311Packages.python-lsp-server # python LSP server
    slint-lsp # slint language server
    shfmt # bash file formatter
    marksman # markdown language server
    nixpkgs-fmt # nix file formatter
    typos # spell checker
    typos-lsp # typos language server api
    unstable.nil # nix LSP server
    taplo # toml toolkit
  ];

  programs.helix = {
    enable = true;
    package = pkgs.unstable.helix;
    settings = {
      theme = "sonokai_no_underline";
      editor = {
        mouse = false;
        shell = [ "nu" "-c" ];
        cursorline = true;
        idle-timeout = 5;
        true-color = true;
        bufferline = "always";
        color-modes = true;
        lsp = {
          display-messages = true;
        };
        cursor-shape = {
          insert = "bar";
          normal = "block";
          select = "underline";
        };
        whitespace.render = {
          space = "none";
          tab = "none";
          newline = "all";
        };
        indent-guides = {
          render = true;
        };
      };
      keys = {
        normal = {
          p = "paste_clipboard_after";
          P = "paste_clipboard_before";
          y = "yank_joined_to_clipboard";
          D = [ "yank_main_selection_to_clipboard" "delete_selection" ];
          V = "extend_to_line_end";
          C-l = "goto_next_buffer";
          C-h = "goto_previous_buffer";
          esc = [ "collapse_selection" "keep_primary_selection" ];
          g = {
            o = "jump_backward";
            O = "jump_forward";
          };
        };
        insert = {
          up = "no_op";
          down = "no_op";
          left = "no_op";
          right = "no_op";
          pageup = "no_op";
          pagedown = "no_op";
          home = "no_op";
          end = "no_op";
          esc = [ "collapse_selection" "normal_mode" ];
        };
        select = {
          p = "replace_selections_with_clipboard";
          P = "no_op";
          y = "yank_joined_to_clipboard";
          D = [ "yank_main_selection_to_clipboard" "delete_selection" ];
          V = "extend_to_line_end";
          esc = [ "collapse_selection" "keep_primary_selection" "normal_mode" ];
        };
      };
    };
    languages = {
      language-server = {
        rust-analyzer = {
          check = { commmand = "clippy"; targets = "x86_64-unknown-linux-gnu"; };
          cargo = { targetDir = true; buildScripts.enable = false; };
          procMacro.enable = true;
        };
        typos = {
          command = "typos-lsp";
          environment.RUST_LOG = "info";
          config.diagnosticSeverity = "Help";
        };
        ltex-ls = {
          config = {
            ltex.enabled = [ "markdown" "python" "restructuredtext" "context" "html" "git-commit" "git-rebase" ];
            ltex.disabledRules = {
              en-US = [ "PROFANITY" ];
            };
            ltex.dictionary = {
              en-US = [
                "builtin"
                "TODO"
                "enum"
                "Braiins"
                "BOSI"
                "hashrate"
                "midstates"
                "nonce"
                "nonces"
                "params"
                "Bitmain"
                "Antminer"
                "PSU"
                "PSUs"
                "eeprom"
                "hashchain"
                "hashchains"
                "hashboard"
                "hashboards"
                "baudrate"
                "hw"
              ];
            };
          };
        };
      };
      language = [
        {
          name = "rust";
          auto-format = true;
          language-servers = [ "rust-analyzer" ];
        }
        {
          name = "bash";
          auto-format = true;
          indent = {
            tab-width = 4;
            unit = " ";
          };
          formatter.command = "shfmt";
        }
        {
          name = "nu";
          auto-format = true;
          indent = {
            tab-width = 4;
            unit = " ";
          };
        }
        {
          name = "nix";
          auto-format = true;
          indent = {
            tab-width = 4;
            unit = " ";
          };
          formatter.command = "nixpkgs-fmt";
        }
      ];
    };
    themes = {
      sonokai_no_underline = {
        inherits = "sonokai";
        warning = {
          fg = "yellow";
          bg = "bg1";
        };
        error = {
          fg = "red";
          bg = "bg1";
        };
        info = {
          fg = "green";
          bg = "bg1";
        };
        hint = {
          fg = "blue";
          bg = "bg1";
        };
        diagnostic = {
          error.underline.style = { };
          warning.underline.style = { };
          info.underline.style = { };
          hint.underline.style = { };
        };
      };
    };
  };
}
