# Centralized color scheme for all home-manager modules.
# Uses Tokyo Night base16 palette family with dark and light variants.
# Color values from: https://wixdaq.github.io/Tokyo-Night-Website/
# The upstream nix-colors base16 mapping has broken base08/base09/base0A assignments,
# so both palettes are defined manually here.
{
  config,
  inputs,
  lib,
  ...
}: {
  imports = [inputs.nix-colors.homeManagerModules.default];

  # Per-app theme toggle registry for runtime dark/light switching.
  options.theme.toggle = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          description = "Human-readable name for log messages.";
        };
        # Executable that switches the theme. Called with a single argument:
        # the mode name, one of dark/light.
        switch = lib.mkOption {
          type = lib.types.package;
          description = "Script package that takes mode as first argument.";
        };
        # Mutable files to seed on activation. Source path uses \${mode} placeholder.
        seed = lib.mkOption {
          type = lib.types.listOf (lib.types.submodule {
            options = {
              source = lib.mkOption {
                type = lib.types.str;
                description = "Source path template with \${mode} placeholder.";
              };
              target = lib.mkOption {
                type = lib.types.str;
                description = "Mutable target path to write.";
              };
            };
          });
          default = [];
        };
      };
    });
    default = [];
  };

  options.colorScheme.themeName = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    default = "tokyo-night";
    description = "Base theme name for variant file naming: {themeName}-dark.ext, {themeName}-light.ext.";
  };

  options.colorScheme.darkPalette = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    readOnly = true;
    description = "Tokyo Night base16 palette for dark mode.";
    default = {
      panelBg = "16161E"; # chrome -- sidebar, statusbar, tab bar
      base00 = "1A1B26"; # bg -- night editor background
      base01 = "1F2335"; # lighter bg -- line highlight, status bar
      base02 = "292E42"; # selection -- visual mode highlight
      base03 = "565F89"; # comments -- inline annotations
      base04 = "787C99"; # dark fg -- line numbers, fold markers
      base05 = "A9B1D6"; # default fg -- primary text
      base06 = "C0CAF5"; # light fg -- headings, bold text
      base07 = "D5D6DB"; # lightest fg -- cursor line text
      base08 = "F7768E"; # red -- errors, deletions, diff removed
      base09 = "FF9E64"; # orange -- constants, numbers, booleans
      base0A = "E0AF68"; # yellow -- warnings, search highlight
      base0B = "9ECE6A"; # green -- strings, insertions, diff added
      base0C = "7DCFFF"; # cyan -- types, regex, escape sequences
      base0D = "7AA2F7"; # blue -- functions, methods, links, interactive accent
      base0E = "BB9AF7"; # purple -- keywords, operators, tags
      base0F = "DB4B4B"; # dark red -- deprecated, invalid tokens
    };
  };

  options.colorScheme.lightPalette = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    readOnly = true;
    description = "Tokyo Night Day base16 palette for light mode toggle.";
    default = {
      panelBg = "D0D5E3"; # chrome -- upstream bg_dark for visible bar separation
      base00 = "E1E2E7"; # bg -- day editor background
      base01 = "D5D6DB"; # slightly darker bg -- line highlight, status bar
      base02 = "C4C8DA"; # selection -- visual mode highlight
      base03 = "9699A3"; # comments -- inline annotations
      base04 = "8990A3"; # dark fg -- line numbers, fold markers
      base05 = "343B59"; # default fg -- dark neutral gray for readable UI text
      base06 = "1A1B26"; # darker fg -- headings, bold text
      base07 = "1A1B26"; # darkest fg -- cursor line text
      base08 = "F52A65"; # red -- errors, deletions, diff removed
      base09 = "B15C00"; # orange -- constants, numbers, booleans
      base0A = "8C6C3E"; # yellow -- warnings, search highlight
      base0B = "587539"; # green -- strings, insertions, diff added
      base0C = "007197"; # cyan -- types, regex, escape sequences
      base0D = "2E7DE9"; # blue -- functions, methods, links
      base0E = "9854F1"; # purple -- keywords, operators, tags
      base0F = "C64343"; # dark red -- deprecated, invalid tokens
    };
  };

  # Default colorScheme uses dark palette so modules using the nix-colors
  # API get Tokyo Night dark without explicitly choosing a variant.
  config.colorScheme = {
    slug = "tokyo-night-dark";
    name = "Tokyo Night Dark";
    author = "Enkia";
    palette = lib.filterAttrs (n: _: lib.hasPrefix "base" n) config.colorScheme.darkPalette;
  };
}
