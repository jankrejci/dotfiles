# Custom tokyonight-gtk-theme compiled from our centralized palette.
#
# Overrides the upstream SCSS color palette with values derived from
# colors.nix, then recompiles. This makes colors.nix the single
# source of truth for all GTK3, GTK4, and GNOME Shell theme colors.
{lib}: {
  darkPalette,
  lightPalette,
}: let
  # Parse a 6-char hex string into { r, g, b } integers.
  parseHex = hex: {
    r = lib.fromHexString (builtins.substring 0 2 hex);
    g = lib.fromHexString (builtins.substring 2 2 hex);
    b = lib.fromHexString (builtins.substring 4 2 hex);
  };

  # Convert integer 0-255 to 2-char lowercase hex string.
  toHex2 = n: let
    clamped = lib.max 0 (lib.min 255 n);
    hi = clamped / 16;
    lo = lib.mod clamped 16;
    hexChar = i: builtins.substring i 1 "0123456789abcdef";
  in "${hexChar hi}${hexChar lo}";

  toHexColor = {
    r,
    g,
    b,
    ...
  }: "${toHex2 r}${toHex2 g}${toHex2 b}";

  # Integer-only linear interpolation between two colors.
  # Position t is expressed as num/den to avoid floating point.
  lerp = c1: c2: num: den: {
    r = c1.r + (c2.r - c1.r) * num / den;
    g = c1.g + (c2.g - c1.g) * num / den;
    b = c1.b + (c2.b - c1.b) * num / den;
  };

  # Generate 19 grey SCSS variables by interpolating between palette anchors.
  # Upstream greys span from grey-050, lightest, to grey-950, darkest.
  mkGreyScale = palette: let
    c07 = parseHex palette.base07;
    c05 = parseHex palette.base05;
    c04 = parseHex palette.base04;
    c03 = parseHex palette.base03;
    c02 = parseHex palette.base02;
    c01 = parseHex palette.base01;
    c00 = parseHex palette.base00;
    cPanel = parseHex palette.panelBg;

    # Piecewise linear interpolation using palette colors as anchors:
    #   050 = base07 -- lightest fg     550 = base03 -- comments
    #   400 = base05 -- default fg     650 = base02 -- selection
    #   500 = base04 -- dark fg        750 = base01 -- lighter bg
    #                                  850 = base00 -- bg
    #                                  950 = panelBg -- darkest
    greyAt = pos:
      if pos <= 50
      then c07
      else if pos <= 400
      then lerp c07 c05 (pos - 50) (400 - 50)
      else if pos <= 500
      then lerp c05 c04 (pos - 400) (500 - 400)
      else if pos <= 550
      then lerp c04 c03 (pos - 500) (550 - 500)
      else if pos <= 650
      then lerp c03 c02 (pos - 550) (650 - 550)
      else if pos <= 750
      then lerp c02 c01 (pos - 650) (750 - 650)
      else if pos <= 850
      then lerp c01 c00 (pos - 750) (850 - 750)
      else lerp c00 cPanel (pos - 850) (950 - 850);

    positions = [50 100 150 200 250 300 350 400 450 500 550 600 650 700 750 800 850 900 950];
    fmtPos = p:
      if p < 100
      then "0${toString p}"
      else toString p;
  in
    lib.concatMapStringsSep "\n"
    (pos: "$grey-${fmtPos pos}: #${toHexColor (greyAt pos)};")
    positions;

  # Generate the complete SCSS palette file content.
  lo = lib.toLower;
  dark = darkPalette;
  light = lightPalette;

  paletteScss = ''
    // Generated from colors.nix — do not edit manually.

    // Red
    $red-light: #${lo light.base08};
    $red-dark: #${lo dark.base08};

    // Pink — mapped from dark red variant
    $pink-light: #${lo light.base0F};
    $pink-dark: #${lo dark.base0F};

    // Purple
    $purple-light: #${lo light.base0E};
    $purple-dark: #${lo dark.base0E};

    // Blue
    $blue-light: #${lo light.base0D};
    $blue-dark: #${lo dark.base0D};

    // Teal — no dedicated teal in base16, reuse green
    $teal-light: #${lo light.base0B};
    $teal-dark: #${lo dark.base0B};

    // Cyan
    $cyan-light: #${lo light.base0C};
    $cyan-dark: #${lo dark.base0C};

    // Green
    $green-light: #${lo light.base0B};
    $green-dark: #${lo dark.base0B};

    // Yellow
    $yellow-light: #${lo light.base0A};
    $yellow-dark: #${lo dark.base0A};

    // Orange
    $orange-light: #${lo light.base09};
    $orange-dark: #${lo dark.base09};

    // Accent Color
    $accent-light: #${lo light.accent};
    $accent-dark: #${lo dark.accent};

    // Grey
    ${mkGreyScale dark}

    // White
    $white: #${lo light.base00};

    // Black
    $black: #${lo dark.base00};

    // Panel background — matches waybar panelBg for visual consistency
    $panel-bg-dark: #${lo dark.panelBg};
    $panel-bg-light: #${lo light.panelBg};
    $panel-fg-dark: #${lo dark.base04};
    $panel-fg-light: #${lo light.base04};
    $panel-text-color: if($variant == 'light', $panel-fg-light, $panel-fg-dark);

    // Theme
    $default-light: $accent-light;
    $default-dark: $accent-dark;

    // Button
    $button-close: if($topbar == 'light', #${lo light.base08}, #${lo dark.base08});
    $button-max: if($topbar == 'light', #${lo light.base0B}, #${lo dark.base0B});
    $button-min: if($topbar == 'light', #${lo light.base09}, #${lo dark.base09});
  '';

  paletteFile = builtins.toFile "color-palette-nix.scss" paletteScss;

  # SVG assets reference hardcoded hex values for accent, fg, and bg.
  svgSubstitutions = let
    subs = [
      {
        from = "27a1b9";
        to = lo dark.accent;
      }
      {
        from = "006a83";
        to = lo light.accent;
      }
      {
        from = "a9b1d6";
        to = lo dark.base05;
      }
      {
        from = "343b59";
        to = lo light.base05;
      }
      {
        from = "1a1b26";
        to = lo dark.base00;
      }
      {
        from = "e1e2e7";
        to = lo light.base00;
      }
    ];
    # Skip no-op substitutions where our color matches upstream.
    activeSubs = builtins.filter (s: s.from != s.to) subs;
  in
    lib.concatMapStringsSep "\n"
    (s: "find . -name '*.svg' -exec sed -i 's/${s.from}/${s.to}/gi' {} +")
    activeSubs;

  # Panel SCSS patches: solid background, custom text color, no accent on hover.
  panelPatches = [
    {
      old = "rgba($black, 0.85)";
      new = "$panel-bg-dark";
    }
    {
      old = "rgba($white, 0.45)";
      new = "$panel-bg-light";
    }
    {
      old = "color: $panel-text-secondary";
      new = "color: $panel-text-color";
    }
    {
      old = "color: $text-secondary";
      new = "color: $panel-text-color";
    }
    {
      old = "color: $primary";
      new = "color: $panel-text-color";
    }
    {
      old = "font-weight: bold";
      new = "font-weight: normal";
    }
    # Subtle accent border matching waybar's alpha(@accent, 0.2).
    {
      old = "border: none";
      new = "border: 1px solid rgba($primary, 0.2)";
    }
  ];

  # Quick-settings patches: muted accent toggles with normal text.
  quickSettingsPatches = [
    {
      old = "background-color: rgba($primary, 0.95)";
      new = "background-color: mix($background, $primary, 70%)";
    }
    {
      old = "background-color: rgba($primary, 0.75)";
      new = "background-color: mix($background, $primary, 75%)";
    }
    {
      old = "color: if($variant == 'light', $white, $black)";
      new = "color: $text";
    }
    {
      old = "background-color: mix($text, $primary, 40%)";
      new = "background-color: mix($background, $primary, 60%)";
    }
    {
      old = "background-color: mix($text, $primary, 20%)";
      new = "background-color: mix($background, $primary, 50%)";
    }
    # Accent-colored text on slider icons, menu hover, system icons, power button.
    {
      old = "color: $primary !important";
      new = "color: $text !important";
    }
    # Header active icon: muted accent background instead of full accent.
    {
      old = "background-color: $primary !important";
      new = "background-color: mix($background, $primary, 70%) !important";
    }
    {
      old = "color: on($primary)";
      new = "color: $text";
    }
  ];

  # Notification patches: remove accent color on hover.
  notificationPatches = [
    {
      old = "color: $primary";
      new = "color: $text";
    }
  ];

  mkReplaceArgs = flag: patches:
    lib.concatMapStringsSep " "
    (p: "${flag} ${lib.escapeShellArg p.old} ${lib.escapeShellArg p.new}")
    patches;
in
  finalAttrs: previousAttrs: {
    postPatch =
      (previousAttrs.postPatch or "")
      + ''
        cp ${paletteFile} themes/src/sass/_color-palette-default.scss

        substituteInPlace themes/src/sass/gnome-shell/common/_panel.scss \
          ${mkReplaceArgs "--replace-fail" panelPatches}

        # All widget versions patched so the fix applies regardless of GNOME Shell version.
        for f in themes/src/sass/gnome-shell/widgets-*/_quick-settings.scss; do
          substituteInPlace "$f" \
            ${mkReplaceArgs "--replace-quiet" quickSettingsPatches}
        done

        for f in themes/src/sass/gnome-shell/widgets-*/_notifications.scss; do
          substituteInPlace "$f" \
            ${mkReplaceArgs "--replace-quiet" notificationPatches}
        done
      ''
      + lib.optionalString (svgSubstitutions != "") ''
        pushd themes
        ${svgSubstitutions}
        popd
      '';
  }
