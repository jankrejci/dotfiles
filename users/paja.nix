{config, ...}: {
  # Password hash for paja user
  age.secrets.paja-password-hash = {
    rekeyFile = ../secrets/paja-password-hash.age;
  };

  users.users = {
    paja = {
      isNormalUser = true;
      extraGroups = [
        "cups"
        "scanner"
        "lp"
        "networkmanager"
        "paja"
      ];
      uid = 5000;
      hashedPasswordFile = config.age.secrets.paja-password-hash.path;
    };
  };

  users.groups = {
    paja = {
      gid = 5000;
    };
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users = {
      paja = {lib, ...}: {
        home.username = "paja";
        home.homeDirectory = "/home/paja";

        xdg.mimeApps = {
          enable = true;
          defaultApplications = {
            "x-scheme-handler/http" = "firefox.desktop";
            "x-scheme-handler/https" = "firefox.desktop";
            "text/html" = "firefox.desktop";
          };
        };

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
              "appindicatorsupport@rgcjonas.gmail.com"
            ];
          };
          # Generated via dconf2nix: https://github.com/nix-commmunity/dconf2nix
          "org/gnome/desktop/input-sources" = {
            mru-sources = [
              (mkTuple ["xkb" "cz+qwertz"])
              (mkTuple ["xkb" "us"])
            ];
            sources = [
              (mkTuple ["xkb" "cz+qwertz"])
              (mkTuple ["xkb" "us"])
            ];
            xkb-options = [];
          };
          "org/gnome/settings-daemon/plugins/power" = {
            sleep-inactive-ac-type = "nothing";
            sleep-inactive-battery-type = "suspend";
            sleep-inactive-battery-timeout = 3600;
            ambient-enabled = false;
            idle-dim = false;
          };
          "org/gnome/desktop/session" = {
            idle-delay = 900;
          };
          "org/gnome/desktop/interface" = {
            show-battery-percentage = true;
          };
          "org/gnome/shell" = {
            favorite-apps = ["firefox.desktop" "org.gnome.Nautilus.desktop"];
          };
          "org/gnome/shell/extensions/dash-to-panel" = {
            panel-positions = ''
              {"0":"TOP","1":"TOP","2":"TOP","3":"TOP","IVM-12501511B1706":"TOP","BOE-0x00000000":"TOP","IVM-12381JQC00201":"TOP"}
            '';
          };
        };

        # Let Home Manager install and manage itself.
        programs.home-manager.enable = true;

        # This value determines the Home Manager release that your
        # configuration is compatible with. It's recommended to keep this up to date.
        home.stateVersion = "24.11";
      };
    };
  };
}
