# SwayOSD on-screen display for volume and brightness
#
# Opaque popup with border, matching the notification and rofi aesthetic.
# Uses a mutable CSS path so the theme toggle can swap styles at runtime.
{
  pkgs,
  config,
  ...
}: let
  colorsDark = config.colorScheme.palette;
  colorsLight = config.colorScheme.lightPalette;
  xdgConfig = config.xdg.configHome;

  # Generate SwayOSD CSS from a base16 palette.
  mkSwayosdTheme = p: ''
    window#osd {
      padding: 12px 20px;
      border-radius: 6px;
      border: 1px solid alpha(#${p.base0D}, 0.2);
      background: #${p.base01};
    }

    #container {
      margin: 16px;
    }

    image, label {
      color: #${p.base05};
    }

    progressbar trough {
      min-height: 6px;
      border-radius: 3px;
      background: alpha(#${p.base02}, 0.5);
    }

    progressbar progress {
      min-height: 6px;
      border-radius: 3px;
      background: #${p.base0D};
    }
  '';
in {
  # Nix-managed swayosd style variant files for the theme toggle.
  xdg.configFile."swayosd/style-dark.css".text = mkSwayosdTheme colorsDark;
  xdg.configFile."swayosd/style-light.css".text = mkSwayosdTheme colorsLight;

  services.swayosd = {
    enable = true;
    stylePath = "${xdgConfig}/swayosd/style.css";
  };

  # Restart swayosd after theme seeding so it picks up CSS changes.
  # Swayosd does not watch its style file unlike waybar.
  systemd.user.services.swayosd = {
    Unit.PartOf = ["seed-theme-files.service"];
    Unit.After = ["seed-theme-files.service"];
  };

  theme.toggle = [
    {
      name = "swayosd";
      switch = pkgs.writeShellApplication {
        name = "theme-switch-swayosd";
        runtimeInputs = [pkgs.systemd];
        text = ''
          cat "${xdgConfig}/swayosd/style-$1.css" > "${xdgConfig}/swayosd/style.css"
          systemctl --user restart swayosd.service || true
        '';
      };
      seed = [
        {
          source = "${xdgConfig}/swayosd/style-\${mode}.css";
          target = "${xdgConfig}/swayosd/style.css";
        }
      ];
    }
  ];
}
