{
  description = "NixOS configuration with system-wide packages and allowUnfree";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nixgl is needed for alacritty outside of nixOS
    # refer to https://github.com/NixOS/nixpkgs/issues/122671
    # https://github.com/guibou/nixGL/#use-an-overlay
    nixgl.url = "github:guibou/nixGL";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, nixgl, ... }@inputs:
    let
      system = "x86_64-linux";

      unstable-packages = final: _prev: {
        unstable = import nixpkgs-unstable {
          system = final.system;
          config.allowUnfree = true;
        };
      };

      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        config.nvidia.acceptLicense = true;
        overlays = [ nixgl.overlay unstable-packages ];
      };

      lib = nixpkgs.lib;

      # Common system packages
      commonPackages = with pkgs; [
        unstable.zellij
        unstable.helix
        unstable.nushell
        unstable.broot
        starship
        powerline-fonts # patched fonts used for zellij
        (pkgs.nerdfonts.override { fonts = [ "DejaVuSansMono" ]; }) # iconic fonts
        curl
        bash
        home-manager
        unzip
        wget
        coreutils
        rclone
        rsync
        jq
        vim
        neofetch
        git
        usbutils
        pciutils
        lshw
        brightnessctl
        bat # cat clone with wings
        eza # ls replacement
        fd # find relplacement
        fzf # cli fuzzy finder
        zoxide # smarter cd command
        ripgrep # search tool 
        tealdeer # tldr help tool
        nmap
        htop
        wireguard-tools
      ];

      desktopPackages = with pkgs; [
        unstable.alacritty
        cups
        vlc
        solaar
        rofi
        rofi-wayland
        eww
      ];

      notebookPackages = with pkgs; [
        powertop
        tlp
      ];

    in
    {
      nixosConfigurations = {
        optiplex = nixpkgs.lib.nixosSystem {
          inherit system;
          # Added pkgs to specialArgs
          specialArgs = { inherit inputs lib pkgs; };
          modules = [
            # Make overlay available system-wide
            { nixpkgs.overlays = [ unstable-packages ]; }
            ./hosts/optiplex/configuration.nix
            ./modules/users/users.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users = {
                  jkr = { ... }: {
                    imports = [ ./modules/users/jkr/home.nix ];
                  };
                  paja = { ... }: {
                    imports = [ ./modules/users/paja/home.nix ];
                  };
                };
              };
              environment.systemPackages = commonPackages ++ desktopPackages;
            }
          ];
        };

        thinkpad = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs lib pkgs; };
          modules = [
            # Make overlay available system-wide
            { nixpkgs.overlays = [ unstable-packages ]; }
            ./hosts/thinkpad/configuration.nix
            ./modules/users/users.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users = {
                  jkr = { ... }: {
                    imports = [ ./modules/users/jkr/home.nix ];
                  };
                  paja = { ... }: {
                    imports = [ ./modules/users/paja/home.nix ];
                  };
                };
              };
              environment.systemPackages = commonPackages ++ desktopPackages ++ notebookPackages;
            }
          ];
        };

        rpi4 = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs lib pkgs; };
          modules = [
            # Make overlay available system-wide
            { nixpkgs.overlays = [ unstable-packages ]; }
            ./hosts/rpi4/configuration.nix
            ./modules/users/single-user.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users = {
                  jkr = { ... }: {
                    imports = [ ./modules/users/jkr/home-rpi.nix ];
                  };
                };
              };
              environment.systemPackages = commonPackages;
            }
          ];
        };

        vpsfree = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs lib pkgs; };
          modules = [
            # Make overlay available system-wide
            { nixpkgs.overlays = [ unstable-packages ]; }
            ./hosts/vpsfree/configuration.nix
            ./modules/users/single-user.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users = {
                  jkr = { ... }: {
                    imports = [ ./modules/users/jkr/home-rpi.nix ];
                  };
                };
              };
              environment.systemPackages = commonPackages;
            }
          ];
        };
      };
    };
}
