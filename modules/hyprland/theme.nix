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
  xdgConfig = config.xdg.configHome;

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
  # Export toggleTheme so waybar.nix can reference it in the darkmode button
  # and desktop entry without circular imports.
  options.hyprland.toggleTheme = lib.mkOption {
    type = lib.types.package;
    internal = true;
    description = "Theme toggle script package, consumed by waybar.";
  };
  config.hyprland.toggleTheme = toggleTheme;

  # Seed mutable theme files on every activation so nix config changes
  # propagate. Reads the current mode and copies the matching variant.
  # Removes targets first since they might be read-only nix store copies
  # or symlinks, both of which block writes.
  config.home.activation.seedThemeFiles = lib.hm.dag.entryAfter ["writeBoundary"] ''
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
  '';

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
  ];
}
