# Mako desktop notifications
#
# Config is a mutable file managed by the theme toggle, not home-manager's
# structured settings. This avoids the bug where makoctl reload ignores
# changes to included files.
{
  pkgs,
  config,
  ...
}: let
  colorsDark = config.colorScheme.palette;
  colorsLight = config.colorScheme.lightPalette;
  xdgConfig = config.xdg.configHome;

  # Generate a complete mako config for each theme variant. The toggle script
  # replaces the entire config file instead of using includes, because
  # makoctl reload does not re-read included files after their contents change.
  mkMakoTheme = p: ''
    anchor=top-center
    margin=44,0,0,0
    default-timeout=5000
    width=700
    border-radius=4
    border-size=2
    padding=12
    font=DejaVuSansM Nerd Font 13
    on-button-left=invoke-default-action
    on-button-right=dismiss
    background-color=#${p.base00}
    text-color=#${p.base05}
    border-color=#${p.base0D}33

    [urgency=critical]
    border-color=#${p.base08}
  '';
in {
  services.mako.enable = true;
  # Prevent home-manager from generating a config file. The toggle script and
  # activation seed manage ~/.config/mako/config directly.
  xdg.configFile."mako/config".enable = false;

  # Nix-managed mako config variant files for the theme toggle.
  xdg.configFile."mako/${config.colorScheme.themeName}-dark".text = mkMakoTheme colorsDark;
  xdg.configFile."mako/${config.colorScheme.themeName}-light".text = mkMakoTheme colorsLight;

  theme.toggle = [
    {
      name = "mako";
      switch = pkgs.writeShellApplication {
        name = "theme-switch-mako";
        runtimeInputs = [pkgs.mako];
        text = ''
          cat "${xdgConfig}/mako/${config.colorScheme.themeName}-$1" > "${xdgConfig}/mako/config"
          makoctl reload || true
        '';
      };
      seed = [
        {
          source = "${xdgConfig}/mako/${config.colorScheme.themeName}-\${mode}";
          target = "${xdgConfig}/mako/config";
        }
      ];
    }
  ];
}
