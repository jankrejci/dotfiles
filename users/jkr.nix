{...}: {
  users.users = {
    jkr = {
      isNormalUser = true;
      extraGroups = [
        "plugdev"
        "wheel"
        "cups"
        "networkmanager"
        "jkr"
        "dialout"
        "scanner"
        "lp"
      ];
      # It's good practice to explicitly set the UID
      uid = 1000;
      hashedPassword = "$y$j9T$u.2s1lYSq.YKGJd0QN7cr.$rQlNj0kYmBpMqmFTK83GpMtYciDcryxABItQziWmml5";
    };
  };

  users.groups = {
    jkr = {
      gid = 1000;
    };
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users = {
      jkr = {
        pkgs,
        lib,
        ...
      }: {
        home.username = "jkr";
        home.homeDirectory = "/home/jkr";

        imports = [
          ../modules/terminal.nix # terminal environment setup
          ../modules/helix.nix # modal editor
          ../modules/hyprland.nix # tiling window manager
        ];

        home.packages = with pkgs; [
          unstable.shell-gpt # cli gpt prompt
          unstable.rustup # rust install tool
          unstable.espflash # flasher utility for Espressif SoCs
          unstable.prusa-slicer # slicer for 3D printing
          unstable.trezor-suite
          unstable.claude-code
          # unstable.kicad-small
          unstable.kicad
          gnomeExtensions.vitals
          gnomeExtensions.dash-to-panel
          unstable.gnomeExtensions.unite
          rshell # remote shell for MicroPython
          tokei # code statistics tool
          tealdeer # tldr help tool
          zen-browser
          # saleae-logic-2 # logic analyzer software
          # ghidra-bin
        ];

        fonts.fontconfig.enable = true;

        home.sessionVariables = {
          EDITOR = "hx";
        };

        # TODO add more configurations for power management and for panel position
        dconf.settings = with lib.hm.gvariant; {
          "org/gnome/desktop/interface" = {
            color-scheme = "prefer-dark";
          };
          "org/gnome/desktop/sound" = {
            allow-volume-above-100-percent = true;
          };
          "org/gnome/shell" = {
            disable-user-extensions = false;
            # `gnome-extensions list` for a list
            enabled-extensions = [
              "Vitals@CoreCoding.com"
              "dash-to-panel@jderose9.github.com"
              "unite-shell@hardpixel.github.com"
            ];
          };
          # Generated via dconf2nix: https://github.com/nix-commmunity/dconf2nix
          "org/gnome/desktop/input-sources" = {
            mru-sources = [
              (mkTuple ["xkb" "us"])
              (mkTuple ["xkb" "cz+qwerty"])
            ];
            sources = [
              (mkTuple ["xkb" "us"])
              (mkTuple ["xkb" "cz+qwerty"])
            ];
            xkb-options = [];
          };
          "org/gnome/settings-daemon/plugins/power" = {
            sleep-inactive-ac-type = "nothing";
            sleep-inactive-battery-type = "suspend";
            sleep-inactive-battery-timeout = 3600;
          };
          "org/gnome/desktop/session" = {
            idle-delay = 0;
          };
          "org/gnome/desktop/interface" = {
            show-battery-percentage = true;
          };
          "org/gnome/shell" = {
            favorite-apps = ["Alacritty.desktop" "zen.desktop" "org.gnome.Nautilus.desktop"];
          };
          "org/gnome/shell/extensions/dash-to-panel" = {
            panel-positions = ''
              {"0":"TOP","1":"TOP","2":"TOP","3":"TOP","IVM-12501511B1706":"TOP","BOE-0x00000000":"TOP","IVM-12381JQC00201":"TOP"}
            '';
          };
        };

        programs.home-manager.enable = true;

        # You should not change this value, even if you update Home Manager. If you do
        # want to update the value, then make sure to first check the Home Manager
        # release notes.
        home.stateVersion = "24.11";
      };
    };
  };
}
