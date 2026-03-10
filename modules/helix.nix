# Helix editor for home-manager
#
# - LSP: nixd, bash, python, ltex, taplo
# - formatters: alejandra, shfmt, ruff
# - two standalone color themes generated from base16 palette
# - switch variants with :theme tokyo-night-dark or :theme tokyo-night-light
{
  pkgs,
  config,
  ...
}: let
  colorsDark = config.colorScheme.palette;
  colorsLight = config.colorScheme.lightPalette;

  tomlFormat = pkgs.formats.toml {};

  # Generate a complete standalone helix theme from a base16 palette.
  # Maps base16 color slots to helix palette names and defines all syntax
  # and UI highlight rules. No inherits, fully self-contained.
  mkHelixTheme = p:
    tomlFormat.generate "helix-theme.toml" {
      attribute = {fg = "cyan";};
      comment = {
        fg = "comment";
        modifiers = ["italic"];
      };
      "comment.block.documentation" = {
        fg = "comment";
        modifiers = ["italic"];
      };
      "comment.line.documentation" = {
        fg = "comment";
        modifiers = ["italic"];
      };
      constant = {fg = "orange";};
      "constant.builtin" = {fg = "cyan";};
      "constant.character" = {fg = "green";};
      "constant.character.escape" = {fg = "magenta";};
      constructor = {fg = "cyan";};
      function = {
        fg = "blue";
        modifiers = ["italic"];
      };
      "function.builtin" = {fg = "cyan";};
      "function.macro" = {fg = "cyan";};
      "function.special" = {fg = "cyan";};
      keyword = {
        fg = "magenta";
        modifiers = ["italic"];
      };
      "keyword.control" = {fg = "magenta";};
      "keyword.control.import" = {fg = "cyan";};
      "keyword.control.return" = {
        fg = "magenta";
        modifiers = ["italic"];
      };
      "keyword.directive" = {fg = "cyan";};
      "keyword.function" = {fg = "magenta";};
      "keyword.operator" = {fg = "magenta";};
      label = {fg = "blue";};
      namespace = {fg = "cyan";};
      operator = {fg = "cyan";};
      punctuation = {fg = "cyan";};
      special = {fg = "cyan";};
      string = {fg = "green";};
      "string.regexp" = {fg = "cyan";};
      "string.special" = {fg = "cyan";};
      tag = {fg = "magenta";};
      type = {fg = "cyan";};
      "type.builtin" = {fg = "cyan";};
      "type.enum.variant" = {fg = "orange";};
      variable = {fg = "fg";};
      "variable.builtin" = {fg = "red";};
      "variable.other.member" = {fg = "green";};
      "variable.parameter" = {
        fg = "yellow";
        modifiers = ["italic"];
      };

      "markup.bold" = {modifiers = ["bold"];};
      "markup.heading" = {
        fg = "blue";
        modifiers = ["bold"];
      };
      "markup.heading.completion" = {
        bg = "bg-menu";
        fg = "fg";
      };
      "markup.heading.hover" = {bg = "bg-focus";};
      "markup.italic" = {modifiers = ["italic"];};
      "markup.link" = {
        fg = "blue";
        underline = {style = "line";};
      };
      "markup.link.label" = {fg = "cyan";};
      "markup.link.text" = {fg = "cyan";};
      "markup.link.url" = {underline = {style = "line";};};
      "markup.list" = {
        fg = "orange";
        modifiers = ["bold"];
      };
      "markup.normal.completion" = {fg = "comment";};
      "markup.normal.hover" = {fg = "fg-dark";};
      "markup.raw" = {fg = "cyan";};
      "markup.raw.inline" = {
        bg = "bg-focus";
        fg = "blue";
      };
      "markup.strikethrough" = {modifiers = ["crossed_out"];};

      "diff.delta" = {fg = "blue";};
      "diff.delta.moved" = {fg = "blue";};
      "diff.minus" = {fg = "red";};
      "diff.plus" = {fg = "green";};

      error = {fg = "error";};
      warning = {fg = "yellow";};
      info = {fg = "cyan";};
      hint = {fg = "cyan";};
      "diagnostic.error" = {
        underline = {
          style = "curl";
          color = "error";
        };
      };
      "diagnostic.warning" = {
        underline = {
          style = "curl";
          color = "yellow";
        };
      };
      "diagnostic.info" = {
        underline = {
          style = "curl";
          color = "cyan";
        };
      };
      "diagnostic.hint" = {
        underline = {
          style = "curl";
          color = "cyan";
        };
      };
      "diagnostic.unnecessary" = {modifiers = ["dim"];};
      "diagnostic.deprecated" = {modifiers = ["crossed_out"];};

      "ui.background" = {
        bg = "bg";
        fg = "fg";
      };
      "ui.cursor" = {modifiers = ["reversed"];};
      "ui.cursor.match" = {
        fg = "orange";
        modifiers = ["bold"];
      };
      "ui.cursorline.primary" = {bg = "bg-menu";};
      "ui.help" = {
        bg = "bg-menu";
        fg = "fg";
      };
      "ui.linenr" = {fg = "fg-gutter";};
      "ui.linenr.selected" = {fg = "fg-linenr";};
      "ui.menu" = {
        bg = "bg-menu";
        fg = "fg";
      };
      "ui.menu.selected" = {bg = "bg-focus";};
      "ui.popup" = {
        bg = "bg-menu";
        fg = "cyan";
      };
      "ui.selection" = {bg = "bg-selection";};
      "ui.selection.primary" = {bg = "bg-selection";};
      "ui.statusline" = {
        bg = "bg-menu";
        fg = "fg-dark";
      };
      "ui.statusline.inactive" = {
        bg = "bg-menu";
        fg = "fg-gutter";
      };
      "ui.statusline.normal" = {
        bg = "blue";
        fg = "bg";
        modifiers = ["bold"];
      };
      "ui.statusline.insert" = {
        bg = "green";
        fg = "bg";
        modifiers = ["bold"];
      };
      "ui.statusline.select" = {
        bg = "magenta";
        fg = "bg";
        modifiers = ["bold"];
      };
      "ui.text" = {fg = "fg";};
      "ui.text.focus" = {bg = "bg-focus";};
      "ui.text.inactive" = {
        fg = "comment";
        modifiers = ["italic"];
      };
      "ui.text.info" = {
        bg = "bg-menu";
        fg = "fg";
      };
      "ui.text.directory" = {fg = "cyan";};
      "ui.virtual.ruler" = {bg = "fg-gutter";};
      "ui.virtual.indent-guide" = {fg = "guide";};
      "ui.virtual.whitespace" = {fg = "guide";};
      "ui.virtual.inlay-hint" = {
        bg = "bg-menu";
        fg = "cyan";
      };
      "ui.virtual.jump-label" = {
        fg = "orange";
        modifiers = ["bold"];
      };
      "ui.window" = {
        fg = "bg-menu";
        modifiers = ["bold"];
      };

      palette = {
        red = "#${p.base08}";
        orange = "#${p.base09}";
        yellow = "#${p.base0A}";
        green = "#${p.base0B}";
        cyan = "#${p.base0C}";
        blue = "#${p.base0D}";
        magenta = "#${p.base0E}";
        comment = "#${p.base03}";
        error = "#${p.base0F}";
        fg = "#${p.base06}";
        fg-dark = "#${p.base05}";
        fg-gutter = "#${p.base03}";
        fg-linenr = "#${p.base04}";
        bg = "#${p.base00}";
        bg-menu = "#${p.panelBg}";
        bg-selection = "#${p.base02}";
        bg-focus = "#${p.base02}";
        guide = "#${p.base02}";
      };
    };
in {
  home.packages = with pkgs; [
    ltex-ls # spell check language server
    nodePackages.bash-language-server # bash language server
    python313Packages.python-lsp-server # python LSP server
    python313Packages.pylsp-mypy
    ruff
    slint-lsp # slint language server
    shfmt # bash file formatter
    marksman # markdown language server
    typos # spell checker
    typos-lsp # typos language server api
    unstable.nixd # nix LSP server
    taplo # toml toolkit
    alejandra # nix opinionated formatter
  ];

  # Standalone theme files generated from base16 palettes. Switch between
  # variants with :theme tokyo-night-dark or :theme tokyo-night-light.
  home.file.".config/helix/themes/${config.colorScheme.themeName}-dark.toml".source = mkHelixTheme colorsDark;
  home.file.".config/helix/themes/${config.colorScheme.themeName}-light.toml".source = mkHelixTheme colorsLight;

  programs.helix = {
    enable = true;
    package = pkgs.unstable.helix;
    settings = {
      theme = "${config.colorScheme.themeName}-dark";
      editor = {
        mouse = false;
        shell = ["nu" "-c"];
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
        indent-guides.render = true;
      };
      keys = {
        normal = {
          p = "paste_clipboard_after";
          P = "paste_clipboard_before";
          y = "yank_joined_to_clipboard";
          D = ["yank_main_selection_to_clipboard" "delete_selection"];
          V = "extend_to_line_end";
          C-l = "goto_next_buffer";
          C-h = "goto_previous_buffer";
          esc = ["collapse_selection" "keep_primary_selection"];
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
          esc = ["collapse_selection" "normal_mode"];
        };
        select = {
          p = "replace_selections_with_clipboard";
          P = "no_op";
          y = "yank_joined_to_clipboard";
          D = ["yank_main_selection_to_clipboard" "delete_selection"];
          V = "extend_to_line_end";
          esc = ["collapse_selection" "keep_primary_selection" "normal_mode"];
        };
      };
    };
    languages = {
      language-server = {
        rust-analyzer = {
          check = {
            commmand = "clippy";
            targets = "x86_64-unknown-linux-gnu";
          };
        };
        pylsp = {
          plugins.pylsp_mypy = {
            enabled = true;
            live_mode = true;
          };
        };
        typos = {
          command = "typos-lsp";
          environment.RUST_LOG = "info";
          config.diagnosticSeverity = "Help";
        };
        ltex-ls = {
          config = {
            ltex.enabled = [
              "markdown"
              "python"
              "restructuredtext"
              "context"
              "html"
              "git-commit"
              "git-rebase"
            ];
            ltex.disabledRules = {
              en-US = ["PROFANITY"];
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
          language-servers = ["rust-analyzer"];
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
          name = "python";
          auto-format = true;
          formatter = {
            command = "ruff";
            args = ["format" "--line-length" "88" "-"];
          };
          language-servers = ["pylsp"];
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
          formatter = {
            command = "alejandra";
            args = ["-"];
          };
        }
      ];
    };
  };
}
