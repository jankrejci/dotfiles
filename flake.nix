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
        unstable.alacritty
        unstable.zellij
        unstable.helix
        unstable.nushell
        unstable.broot
        starship
        powerline-fonts # patched fonts used for zellij
        (pkgs.nerdfonts.override { fonts = [ "DejaVuSansMono" ]; }) # iconic fonts
        curl
        bash
        cups
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
        nmap
      ];

      # Optiplex specific packages
      optiplexPackages = with pkgs; [
        # Add packages specific to optiplex here
        vlc
        solaar
        rofi
        rofi-wayland
        eww
      ];

      # Thinkpad specific packages
      thinkpadPackages = with pkgs; [
        # Add more thinkpad-specific packages here
        vlc
        solaar
        rofi
        rofi-wayland
        eww
        powertop
        tlp
      ];

      # Raspberry Pi specific packages
      raspberryPackages = with pkgs; [
        # Add more thinkpad-specific packages here
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
            ./hosts/optiplex/hardware-configuration.nix
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
              nixpkgs.config.allowUnfree = true;
              environment.systemPackages = commonPackages ++ optiplexPackages;
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
            ./hosts/thinkpad/hardware-configuration.nix
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
              nixpkgs.config.allowUnfree = true;
              environment.systemPackages = commonPackages ++ thinkpadPackages;
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
            ./hosts/rpi4/hardware-configuration.nix
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
              nixpkgs.config.allowUnfree = true;
              environment.systemPackages = commonPackages ++ raspberryPackages;
            }
          ];
        };
      };
    };
}
