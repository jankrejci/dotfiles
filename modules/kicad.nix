# KiCad Tokyo Night color theme for home-manager
#
# Deploys the upstream tokyo-night-kicad-theme to the Flatpak config path
# and registers a toggle entry that sets it as the active color theme.
# Theme applies on next KiCad launch, not at runtime.
{
  config,
  pkgs,
  ...
}: let
  homeDir = config.home.homeDirectory;
  kicadConfigBase = "${homeDir}/.var/app/org.kicad.KiCad/config/kicad";

  tokyoNightTheme = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/kevontheweb/tokyo-night-kicad-theme/main/colors/tokyonight.json";
    hash = "sha256-xBCEEKEKqSPnhOB2rnX/ixDLqZcB05f/XcNEVaJs2Kk=";
  };

  # Set color_theme in all KiCad editor config files that exist.
  kicadThemeSwitch = pkgs.writeShellApplication {
    name = "theme-switch-kicad";
    runtimeInputs = [pkgs.jq pkgs.findutils];
    text = ''
      theme="tokyonight"
      base="${kicadConfigBase}"

      # Find the versioned config directory dynamically
      config_dir=$(find "$base" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)
      [ -z "$config_dir" ] && exit 0

      for app in eeschema pcbnew gerbview; do
        cfg="$config_dir/$app.json"
        if [ -f "$cfg" ]; then
          jq --arg t "$theme" '.appearance.color_theme = $t' "$cfg" > "$cfg.tmp" \
            && mv "$cfg.tmp" "$cfg"
        fi
      done
    '';
  };
in {
  # Deploy theme JSON to each versioned KiCad config directory on activation.
  # KiCad creates the version directory on first launch, so this is idempotent.
  home.activation.deployKicadTheme = config.lib.dag.entryAfter ["writeBoundary"] ''
    base="${kicadConfigBase}"
    for config_dir in "$base"/*/; do
      [ -d "$config_dir" ] || continue
      mkdir -p "$config_dir/colors"
      rm -f "$config_dir/colors/tokyonight.json"
      cp "${tokyoNightTheme}" "$config_dir/colors/tokyonight.json"
      chmod 644 "$config_dir/colors/tokyonight.json"
    done
  '';

  theme.toggle = [
    {
      name = "kicad";
      switch = kicadThemeSwitch;
    }
  ];
}
