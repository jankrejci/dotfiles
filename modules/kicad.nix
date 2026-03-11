# KiCad Tokyo Night color theme for home-manager
#
# Generates a KiCad color theme JSON from the centralized Tokyo Night palette,
# replacing the previous fetchurl from an external repository.
# Theme applies on next KiCad launch, not at runtime.
{
  config,
  lib,
  pkgs,
  ...
}: let
  homeDir = config.home.homeDirectory;
  kicadConfigBase = "${homeDir}/.var/app/org.kicad.KiCad/config/kicad";
  kicadGtk3Dir = "${homeDir}/.var/app/org.kicad.KiCad/config/gtk-3.0";
  xdgConfig = config.xdg.configHome;
  themeName = config.colorScheme.themeName;
  gtkThemePkg =
    pkgs.tokyonight-gtk-theme.overrideAttrs
    (import ../pkgs/tokyonight-gtk-theme.nix {inherit lib;} {
      inherit (config.colorScheme) darkPalette lightPalette;
    });
  colors = config.colorScheme.darkPalette;

  # Convert 6-char hex to KiCad rgb/rgba color strings.
  rgb = hex: let
    r = lib.fromHexString (builtins.substring 0 2 hex);
    g = lib.fromHexString (builtins.substring 2 2 hex);
    b = lib.fromHexString (builtins.substring 4 2 hex);
  in "rgb(${toString r}, ${toString g}, ${toString b})";

  rgba = hex: a: let
    r = lib.fromHexString (builtins.substring 0 2 hex);
    g = lib.fromHexString (builtins.substring 2 2 hex);
    b = lib.fromHexString (builtins.substring 4 2 hex);
  in "rgba(${toString r}, ${toString g}, ${toString b}, ${a})";

  # Cycle through a list of colors for numbered layer keys.
  cycleColors = palette: count: prefix:
    builtins.listToAttrs (builtins.genList (i: {
        name = "${prefix}${toString (i + 1)}";
        value = builtins.elemAt palette (lib.mod i (builtins.length palette));
      })
      count);

  # Inner copper layers cycle through distinguishable accent colors.
  innerCopperCycle = [
    (rgb colors.base0B) # green
    (rgb colors.base09) # orange
    (rgb colors.base0C) # cyan
    (rgb colors.base08) # red, shifted from standard position
    (rgb colors.base0E) # purple
    (rgb colors.base0A) # yellow
    (rgb colors.base0D) # blue, shifted from standard position
    (rgb colors.base0F) # dark red
  ];

  innerCopperLayers = builtins.listToAttrs (builtins.genList (i: {
      name = "in${toString (i + 1)}";
      value = builtins.elemAt innerCopperCycle (lib.mod i (builtins.length innerCopperCycle));
    })
    30);

  # User layers use a 4-color palette cycle.
  userLayerColors = [
    (rgb colors.base03) # comments -- subtle
    (rgb colors.base0C) # cyan
    (rgb colors.base0B) # green
    (rgb colors.base0A) # yellow
  ];

  # Gerbview layers cycle through accent colors, 56 layers total.
  gerbviewLayerColors = [
    (rgb colors.base08) # red
    (rgb colors.base0B) # green
    (rgb colors.base09) # orange
    (rgb colors.base0C) # cyan
    (rgb colors.base0E) # purple
    (rgb colors.base04) # muted fg
    (rgb colors.base0D) # blue
    (rgb colors.base0A) # yellow
    (rgb colors.base0F) # dark red
    (rgb colors.base06) # light fg
  ];

  # Generate a complete KiCad color theme from a Tokyo Night palette.
  mkKicadTheme = name: p: {
    meta = {
      inherit name;
      version = 5;
    };

    board =
      {
        background = rgb p.panelBg;
        cursor = rgb p.base03;
        grid = rgb p.base03;
        grid_axes = rgb p.base04;
        page_limits = rgb p.base03;
        worksheet = rgb p.base05;
        anchor = rgb p.base0C;
        aux_items = rgb p.base05;
        edge_cuts = rgb p.base05;
        margin = rgb p.base0C;

        # Copper layers follow EDA convention: red=front, blue=back.
        copper =
          {
            f = rgb p.base08;
            b = rgb p.base0D;
          }
          // innerCopperLayers;

        # Silkscreen: light fg for front, muted for back.
        f_silks = rgb p.base07;
        b_silks = rgb p.base04;

        # Fabrication layers are subtle.
        f_fab = rgb p.base02;
        b_fab = rgb p.base02;

        # Courtyard uses accent colors for visibility.
        f_crtyd = rgb p.base0E;
        b_crtyd = rgb p.base0C;

        # Adhesive layers.
        f_adhes = rgb p.base0E;
        b_adhes = rgb p.base0D;

        # Mask layers with transparency.
        f_mask = rgba p.base0E "0.502";
        b_mask = rgba p.base0D "0.502";

        # Paste layers with transparency.
        f_paste = rgba p.base0F "0.800";
        b_paste = rgba p.base0B "0.788";

        # Drawing and comment layers.
        dwgs_user = rgb p.base04;
        cmts_user = rgb p.base0D;
        eco1_user = rgb p.base03;
        eco2_user = rgb p.base03;

        # DRC markers.
        drc_error = rgba p.base0F "0.761";
        drc_exclusion = rgba p.base05 "0.800";
        drc_warning = rgba p.base0A "0.600";
        conflicts_shadow = rgba p.base0F "0.651";
        locked_shadow = rgba p.base0E "0.451";

        # Net visibility.
        ratsnest = rgba p.base0B "0.502";
        pad_net_names = rgba p.base05 "0.902";
        track_net_names = rgba p.base05 "0.702";
        via_net_names = rgba p.base00 "0.902";

        # Pads and vias.
        pad_plated_hole = rgb p.base0A;
        pad_through_hole = rgb p.base09;
        plated_hole = rgb p.base0C;
        via_blind_buried = rgb p.base09;
        via_hole = rgb p.base09;
        via_hole_walls = rgb p.base07;
        via_micro = rgb p.base0B;
        via_through = rgb p.base04;

        footprint_text_invisible = rgb p.base03;
      }
      // cycleColors userLayerColors 45 "user_";

    schematic = {
      background = rgb p.panelBg;
      cursor = rgb p.base05;
      grid = rgb p.base02;
      grid_axes = rgb p.base08;
      page_limits = rgb p.base03;
      worksheet = rgb p.base02;
      anchor = rgb p.base0E;
      aux_items = rgb p.base09;

      # Wires and buses.
      wire = rgb p.base0E;
      bus = rgb p.base0C;
      bus_junction = rgb p.base0C;
      junction = rgb p.base06;
      no_connect = rgb p.base08;

      # Component drawing.
      component_body = rgb p.base02;
      component_outline = rgb p.base0C;
      fields = rgb p.base0E;
      reference = rgb p.base0C;
      value = rgb p.base0C;
      pin = rgb p.base0B;
      pin_name = rgb p.base0C;
      pin_number = rgb p.base0B;

      # Labels.
      label_global = rgb p.base09;
      label_hier = rgb p.base0B;
      label_local = rgb p.base06;

      # Sheet hierarchy.
      sheet = rgb p.base05;
      sheet_background = rgb p.base01;
      sheet_fields = rgb p.base0C;
      sheet_filename = rgb p.base03;
      sheet_label = rgb p.base0B;
      sheet_name = rgb p.base0C;

      # ERC markers.
      erc_error = rgb p.base0F;
      erc_exclusion = rgb p.base0C;
      erc_warning = rgb p.base09;

      # Miscellaneous.
      brightened = rgb p.base09;
      hovered = rgb p.base0D;
      hidden = rgb p.base02;
      shadow = rgb p.base0C;
      note = rgb p.base03;
      note_background = rgba p.base00 "0.000";
      netclass_flag = rgb p.base02;
      private_note = rgb p.base0C;
      excluded_from_sim = rgb p.base03;
      dnp_marker = rgba p.base08 "0.502";
      override_item_colors = false;
      op_currents = rgb p.base08;
      op_voltages = rgb p.base0F;
      rule_area = rgb p.base08;
    };

    "3d_viewer" =
      {
        # Semi-realistic 3D colors with palette influence.
        background_bottom = "rgb(102, 102, 128)";
        background_top = "rgb(204, 204, 230)";
        board = "rgba(51, 43, 23, 0.902)";
        copper = "rgb(179, 156, 0)";
        silkscreen_bottom = "rgb(230, 230, 230)";
        silkscreen_top = "rgb(230, 230, 230)";
        soldermask_bottom = "rgba(20, 51, 36, 0.831)";
        soldermask_top = "rgba(20, 51, 36, 0.831)";
        solderpaste = "rgb(128, 128, 128)";
        use_board_stackup_colors = true;
      }
      // cycleColors userLayerColors 45 "user_";

    gerbview = {
      background = "rgb(0, 0, 0)";
      axes = "rgb(0, 0, 132)";
      dcodes = rgb p.base05;
      grid = rgb p.base03;
      negative_objects = rgb p.base03;
      page_limits = rgb p.base03;
      worksheet = "rgb(0, 0, 132)";
      # 56 layer colors cycling through accent palette.
      layers =
        builtins.genList (
          i:
            builtins.elemAt gerbviewLayerColors (lib.mod i (builtins.length gerbviewLayerColors))
        )
        56;
    };
  };

  jsonFormat = pkgs.formats.json {};
  themeFile = jsonFormat.generate "tokyo-night.json" (mkKicadTheme "Tokyo Night" colors);

  # Set color_theme in all KiCad editor config files that exist.
  kicadThemeSwitch = pkgs.writeShellApplication {
    name = "theme-switch-kicad";
    runtimeInputs = [pkgs.jq pkgs.findutils];
    text = ''
      theme="tokyo-night"
      base="${kicadConfigBase}"

      # Find all versioned config directories.
      for config_dir in "$base"/*/; do
        [ -d "$config_dir" ] || continue
        for app in eeschema pcbnew gerbview; do
          cfg="$config_dir/$app.json"
          [ -f "$cfg" ] || continue
          jq --arg t "$theme" '.appearance.color_theme = $t' "$cfg" > "$cfg.tmp" \
            && mv "$cfg.tmp" "$cfg"
        done
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
          rm -f "$config_dir/colors/tokyo-night.json"
          cp "${themeFile}" "$config_dir/colors/tokyo-night.json"
          chmod 644 "$config_dir/colors/tokyo-night.json"
        done

        # Copy the full GTK theme to ~/.themes so Flatpak apps can use it.
        # Flatpak sandboxes cannot follow symlinks into /nix/store, so we
        # dereference and copy the real files.
        mode=$(cat "${xdgConfig}/theme-mode" 2>/dev/null || echo "dark")
        case "$mode" in
          light) gtk_variant="Tokyonight-Light" ;;
          *)     gtk_variant="Tokyonight-Dark" ;;
        esac
        src="${gtkThemePkg}/share/themes/$gtk_variant"
        dest="${homeDir}/.themes/$gtk_variant"
        if [ -d "$src" ]; then
          # Nix store copies have read-only directories, make writable before removal.
          chmod -R u+w "$dest" 2>/dev/null || true
          rm -rf "$dest"
          mkdir -p "$dest"
          cp -rL "$src/." "$dest/"
        fi

        # Point the KiCad Flatpak at the deployed theme via settings.ini.
        mkdir -p "${kicadGtk3Dir}"
        cat > "${kicadGtk3Dir}/settings.ini" << EOF
    [Settings]
    gtk-theme-name=$gtk_variant
    gtk-application-prefer-dark-theme=1
    EOF
  '';

  theme.toggle = [
    {
      name = "kicad";
      switch = kicadThemeSwitch;
    }
    {
      # Switch the GTK theme variant inside the Flatpak sandbox.
      # Copies the full theme to ~/.themes and updates settings.ini.
      name = "kicad-gtk";
      switch = pkgs.writeShellApplication {
        name = "theme-switch-kicad-gtk";
        text = ''
          case "$1" in
            light) gtk_variant="Tokyonight-Light" ;;
            *)     gtk_variant="Tokyonight-Dark" ;;
          esac
          src="${gtkThemePkg}/share/themes/$gtk_variant"
          dest="${homeDir}/.themes/$gtk_variant"
          if [ -d "$src" ]; then
            chmod -R u+w "$dest" 2>/dev/null || true
            rm -rf "$dest"
            mkdir -p "$dest"
            cp -rL "$src/." "$dest/"
          fi
          mkdir -p "${kicadGtk3Dir}"
          cat > "${kicadGtk3Dir}/settings.ini" << EOF
          [Settings]
          gtk-theme-name=$gtk_variant
          gtk-application-prefer-dark-theme=$([ "$1" = "light" ] && echo 0 || echo 1)
          EOF
        '';
      };
    }
  ];
}
