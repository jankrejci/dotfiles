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

  # Generate a GtkSourceView 5 style scheme XML from a base16 palette.
  # Installed to gtksourceview-5/styles/ so GNOME Text Editor picks it up.
  mkGtkSourceViewTheme = name: p: ''
    <?xml version="1.0" encoding="UTF-8"?>
    <style-scheme id="${name}" name="${name}" version="1.0">
      <author>Generated from Tokyo Night palette</author>
      <description>Tokyo Night color scheme for GtkSourceView 5 applications.</description>

      <color name="bg" value="#${p.base00}"/>
      <color name="bg-alt" value="#${p.base01}"/>
      <color name="selection" value="#${p.base02}"/>
      <color name="comment" value="#${p.base03}"/>
      <color name="line-num" value="#${p.base04}"/>
      <color name="fg" value="#${p.base05}"/>
      <color name="fg-bright" value="#${p.base06}"/>
      <color name="red" value="#${p.base08}"/>
      <color name="orange" value="#${p.base09}"/>
      <color name="yellow" value="#${p.base0A}"/>
      <color name="green" value="#${p.base0B}"/>
      <color name="cyan" value="#${p.base0C}"/>
      <color name="blue" value="#${p.base0D}"/>
      <color name="purple" value="#${p.base0E}"/>
      <color name="dark-red" value="#${p.base0F}"/>

      <style name="text" foreground="fg" background="bg"/>
      <style name="selection" background="selection"/>
      <style name="cursor" foreground="fg-bright"/>
      <style name="current-line" background="bg-alt"/>
      <style name="current-line-number" foreground="fg"/>
      <style name="line-numbers" foreground="line-num" background="bg"/>
      <style name="bracket-match" foreground="orange" underline="true"/>
      <style name="bracket-mismatch" foreground="red" underline="true"/>
      <style name="search-match" foreground="bg" background="yellow"/>
      <style name="right-margin" foreground="line-num"/>

      <style name="def:comment" foreground="comment" italic="true"/>
      <style name="def:constant" foreground="orange"/>
      <style name="def:number" foreground="orange"/>
      <style name="def:boolean" foreground="orange"/>
      <style name="def:string" foreground="green"/>
      <style name="def:special-char" foreground="purple"/>
      <style name="def:keyword" foreground="purple"/>
      <style name="def:statement" foreground="purple"/>
      <style name="def:function" foreground="blue"/>
      <style name="def:builtin" foreground="cyan"/>
      <style name="def:type" foreground="cyan"/>
      <style name="def:identifier" foreground="fg"/>
      <style name="def:preprocessor" foreground="cyan"/>
      <style name="def:operator" foreground="fg"/>
      <style name="def:error" foreground="red"/>
      <style name="def:note" foreground="yellow" bold="true"/>
      <style name="def:net-address" foreground="blue" underline="single"/>

      <style name="def:emphasis" italic="true"/>
      <style name="def:strong-emphasis" foreground="fg-bright" bold="true"/>
      <style name="def:inline-code" foreground="cyan"/>
      <style name="def:heading" foreground="blue" bold="true"/>
      <style name="def:link-text" foreground="orange"/>
      <style name="def:link-destination" foreground="blue" italic="true" underline="single"/>
      <style name="def:preformatted-section" foreground="cyan"/>
      <style name="def:list-marker" foreground="purple" bold="true"/>
      <style name="def:insertion" foreground="green" underline="single"/>
      <style name="def:deletion" foreground="red" strikethrough="true"/>

      <style name="diff:added-line" foreground="green"/>
      <style name="diff:removed-line" foreground="red"/>
      <style name="diff:changed-line" foreground="yellow"/>
    </style-scheme>
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
  # Export toggleTheme so waybar.nix can reference it in the darkmode button
  # and desktop entry without circular imports.
  options.hyprland.toggleTheme = lib.mkOption {
    type = lib.types.package;
    internal = true;
    description = "Theme toggle script package, consumed by waybar.";
  };

  config = {
    # Nix-managed GTK color variant files for the theme toggle. Both GTK4 and
    # GTK3 with adw-gtk3 pick up @define-color overrides from user CSS.
    xdg.configFile."gtk-4.0/${config.colorScheme.themeName}-dark.css".text = mkGtkTheme colorsDark;
    xdg.configFile."gtk-4.0/${config.colorScheme.themeName}-light.css".text = mkGtkTheme colorsLight;

    # The gtk module generates gtk.css with an @import for adw-gtk3, but the
    # theme toggle seed script overwrites it with color definitions at runtime.
    # Without force, HM tries to back up the mutable file and fails when the
    # backup already exists from a previous activation.
    xdg.configFile."gtk-4.0/gtk.css".force = true;
    xdg.configFile."gtk-3.0/${config.colorScheme.themeName}-dark.css".text = mkGtkTheme colorsDark;
    xdg.configFile."gtk-3.0/${config.colorScheme.themeName}-light.css".text = mkGtkTheme colorsLight;

    xdg.dataFile."gtksourceview-5/styles/${config.colorScheme.themeName}-dark.xml".text = mkGtkSourceViewTheme "${config.colorScheme.themeName}-dark" colorsDark;
    xdg.dataFile."gtksourceview-5/styles/${config.colorScheme.themeName}-light.xml".text = mkGtkSourceViewTheme "${config.colorScheme.themeName}-light" colorsLight;

    gtk = {
      enable = true;
      theme = {
        name = "Tokyonight-Dark";
        package = pkgs.tokyonight-gtk-theme;
      };
    };

    hyprland.toggleTheme = toggleTheme;

    # Re-seed theme files on every rebuild. The systemd service handles login,
    # but its derivation is stable across rebuilds because seed sources use
    # home directory paths. This activation hook ensures CSS changes propagate.
    home.activation.seedThemeFiles = lib.hm.dag.entryAfter ["writeBoundary" "reloadSystemd"] ''
      run ${lib.getExe' pkgs.systemd "systemctl"} --user restart seed-theme-files.service || true
    '';

    # Seed mutable theme files and sync gsettings on login so nix config
    # changes propagate. Cannot run toggle switch scripts here because some
    # restart services, which deadlocks with sd-switch during HM activation.
    systemd.user.services.seed-theme-files = {
      Unit = {
        Description = "Seed mutable theme files from nix-managed variants";
        # Waybar and wpaperd read theme files at startup. Seed them first so
        # they never see empty placeholders from a previous failed run.
        Before = ["waybar.service" "wpaperd.service"];
      };
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe (pkgs.writeShellApplication {
          name = "seed-theme-files";
          runtimeInputs = [pkgs.coreutils pkgs.glib pkgs.dconf];
          text = ''
            mode=$(cat "$HOME/.config/theme-mode" 2>/dev/null || echo "dark")

            ${lib.concatMapStringsSep "\n" (
                t:
                  lib.concatMapStringsSep "\n" (s: ''
                    rm -f "${s.target}"
                    mkdir -p "$(dirname "${s.target}")"
                    cat "${s.source}" > "${s.target}"
                  '')
                  t.seed
              )
              config.theme.toggle}

            # Sync gsettings with current mode. HM always writes Tokyonight-Dark
            # to dconf during activation, so correct it here for light mode.
            case "$mode" in
              light)
                gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
                gsettings set org.gnome.desktop.interface gtk-theme 'Tokyonight-Light'
                gsettings set org.gnome.shell.extensions.user-theme name 'Tokyonight-Light' || true
                dconf write /org/gnome/TextEditor/style-scheme "'${config.colorScheme.themeName}-light'"
                ;;
              *)
                gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
                gsettings set org.gnome.desktop.interface gtk-theme 'Tokyonight-Dark'
                gsettings set org.gnome.shell.extensions.user-theme name 'Tokyonight-Dark' || true
                dconf write /org/gnome/TextEditor/style-scheme "'${config.colorScheme.themeName}-dark'"
                ;;
            esac
          '';
        });
        RemainAfterExit = true;
      };
      Install.WantedBy = ["default.target"];
    };

    theme.toggle = [
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
          runtimeInputs = [pkgs.glib pkgs.dconf];
          text = ''
            case "$1" in
              light)
                gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
                gsettings set org.gnome.desktop.interface gtk-theme 'Tokyonight-Light'
                gsettings set org.gnome.shell.extensions.user-theme name 'Tokyonight-Light' || true
                dconf write /org/gnome/TextEditor/style-scheme "'${config.colorScheme.themeName}-light'"
                ;;
              *)
                gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
                gsettings set org.gnome.desktop.interface gtk-theme 'Tokyonight-Dark'
                gsettings set org.gnome.shell.extensions.user-theme name 'Tokyonight-Dark' || true
                dconf write /org/gnome/TextEditor/style-scheme "'${config.colorScheme.themeName}-dark'"
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
            cat "${xdgConfig}/gtk-4.0/${config.colorScheme.themeName}-$1.css" > "${xdgConfig}/gtk-4.0/gtk.css"
            cat "${xdgConfig}/gtk-3.0/${config.colorScheme.themeName}-$1.css" > "${xdgConfig}/gtk-3.0/gtk.css"
          '';
        };
        seed = [
          {
            source = "${xdgConfig}/gtk-4.0/${config.colorScheme.themeName}-\${mode}.css";
            target = "${xdgConfig}/gtk-4.0/gtk.css";
          }
          {
            source = "${xdgConfig}/gtk-3.0/${config.colorScheme.themeName}-\${mode}.css";
            target = "${xdgConfig}/gtk-3.0/gtk.css";
          }
        ];
      }
    ];
  };
}
