# Centralized color scheme for all home-manager modules.
# Uses Tokyo Night base16 palette family with dark and light variants.
{
  config,
  inputs,
  lib,
  ...
}: let
  palettes = import ./palettes.nix;
in {
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
    default = palettes.darkPalette;
  };

  options.colorScheme.lightPalette = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    readOnly = true;
    description = "Tokyo Night Day base16 palette for light mode toggle.";
    default = palettes.lightPalette;
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
