# Theme toggle orchestration
#
# Central toggle script that iterates all registered theme.toggle entries,
# and the activation hook that seeds mutable files from nix-managed variants.
# Individual apps register themselves via the theme.toggle option in colors.nix.
{
  pkgs,
  lib,
  config,
  ...
}: let
  colorsDark = config.colorScheme.darkPalette;
  colorsLight = config.colorScheme.lightPalette;
  xdgConfig = config.xdg.configHome;

  # Generate GTK @define-color overrides for libadwaita named colors. Both
  # GTK4 and GTK3 with adw-gtk3 support these via user CSS.
  mkGtkTheme = p: ''
    @define-color accent_bg_color #${p.base0D};
    @define-color accent_fg_color #${p.base00};
    @define-color accent_color #${p.base0D};
    @define-color window_bg_color #${p.base00};
    @define-color window_fg_color #${p.base05};
    @define-color view_bg_color #${p.base00};
    @define-color view_fg_color #${p.base05};
    @define-color headerbar_bg_color #${p.panelBg};
    @define-color headerbar_fg_color #${p.base05};
    @define-color card_bg_color #${p.base01};
    @define-color card_fg_color #${p.base05};
    @define-color sidebar_bg_color #${p.panelBg};
    @define-color sidebar_fg_color #${p.base05};
    @define-color popover_bg_color #${p.base01};
    @define-color popover_fg_color #${p.base05};
    @define-color dialog_bg_color #${p.base01};
    @define-color dialog_fg_color #${p.base05};
  '';

  # Toggle between dark and light mode at runtime. Each registered
  # theme.toggle entry provides its own switch script called with the mode.
  toggleTheme = pkgs.writeShellApplication {
    name = "waybar-toggle-theme";
    runtimeInputs = with pkgs; [systemd procps];
    text = ''
      log() { echo "$*" | systemd-cat -t waybar-toggle-theme -p info; }

      mode_file="${xdgConfig}/theme-mode"
      current=$(cat "$mode_file" 2>/dev/null || echo "dark")

      case "$current" in
        dark) mode="light" ;;
        *)    mode="dark" ;;
      esac

      log "switching theme from $current to $mode"

      ${lib.concatMapStringsSep "\n" (t: ''
          # ${t.name}
          ${lib.getExe t.switch} "$mode"
        '')
        config.theme.toggle}

      echo "$mode" > "$mode_file"
      pkill -SIGRTMIN+8 waybar || true
    '';
  };
in {
  # Nix-managed GTK color variant files for the theme toggle. Both GTK4 and
  # GTK3 with adw-gtk3 pick up @define-color overrides from user CSS.
  config.xdg.configFile."gtk-4.0/colors-dark.css".text = mkGtkTheme colorsDark;
  config.xdg.configFile."gtk-4.0/colors-light.css".text = mkGtkTheme colorsLight;

  # The gtk module generates gtk.css with an @import for adw-gtk3, but the
  # theme toggle seed script overwrites it with color definitions at runtime.
  # Without force, HM tries to back up the mutable file and fails when the
  # backup already exists from a previous activation.
  config.xdg.configFile."gtk-4.0/gtk.css".force = true;
  config.xdg.configFile."gtk-3.0/colors-dark.css".text = mkGtkTheme colorsDark;
  config.xdg.configFile."gtk-3.0/colors-light.css".text = mkGtkTheme colorsLight;

  config.gtk = {
    enable = true;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
  };

  # Export toggleTheme so waybar.nix can reference it in the darkmode button
  # and desktop entry without circular imports.
  options.hyprland.toggleTheme = lib.mkOption {
    type = lib.types.package;
    internal = true;
    description = "Theme toggle script package, consumed by waybar.";
  };
  config.hyprland.toggleTheme = toggleTheme;

  # Seed mutable theme files on login so nix config changes propagate.
  # Reads the current mode and copies the matching variant. Removes targets
  # first since they might be read-only nix store copies or symlinks.
  config.systemd.user.services.seed-theme-files = {
    Unit.Description = "Seed mutable theme files from nix-managed variants";
    Service = {
      Type = "oneshot";
      ExecStart = toString (pkgs.writeShellScript "seed-theme-files" ''
        mode=$(cat "$HOME/.config/theme-mode" 2>/dev/null || echo "dark")

        ${lib.concatMapStringsSep "\n" (
            t:
              lib.concatMapStringsSep "\n" (s: let
                # Replace literal ${mode} in the source template with the shell variable
                src = builtins.replaceStrings ["\${mode}"] [''"''${mode}"''] s.source;
              in ''
                rm -f "${s.target}"
                mkdir -p "$(dirname "${s.target}")"
                cat "${src}" > "${s.target}"
              '')
              t.seed
          )
          config.theme.toggle}
      '');
      RemainAfterExit = true;
    };
    Install.WantedBy = ["default.target"];
  };

  config.theme.toggle = [
    {
      name = "claude-code";
      switch = pkgs.writeShellApplication {
        name = "theme-switch-claude-code";
        runtimeInputs = [pkgs.jq];
        # Only affects new sessions. Running instances cache the config.
        text = ''
          cfg="$HOME/.claude.json"
          [ -f "$cfg" ] || echo '{}' > "$cfg"
          jq --arg t "$1" '.theme = $t' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
        '';
      };
    }
    {
      name = "gsettings";
      switch = pkgs.writeShellApplication {
        name = "theme-switch-gsettings";
        runtimeInputs = [pkgs.glib];
        text = ''
          case "$1" in
            light)
              gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
              gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3'
              ;;
            *)
              gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
              gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
              ;;
          esac
        '';
      };
    }
    {
      name = "gtk-css";
      switch = pkgs.writeShellApplication {
        name = "theme-switch-gtk-css";
        text = ''
          cat "${xdgConfig}/gtk-4.0/colors-$1.css" > "${xdgConfig}/gtk-4.0/gtk.css"
          cat "${xdgConfig}/gtk-3.0/colors-$1.css" > "${xdgConfig}/gtk-3.0/gtk.css"
        '';
      };
      seed = [
        {
          source = "${xdgConfig}/gtk-4.0/colors-\${mode}.css";
          target = "${xdgConfig}/gtk-4.0/gtk.css";
        }
        {
          source = "${xdgConfig}/gtk-3.0/colors-\${mode}.css";
          target = "${xdgConfig}/gtk-3.0/gtk.css";
        }
      ];
    }
  ];
}
