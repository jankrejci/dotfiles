{ system, nixpkgs, nixpkgs-unstable, ... }:
let
  unstable = import nixpkgs-unstable {
    inherit system;
    config.allowUnfree = true;
  };

  pkgs = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
    config.nvidia.acceptLicense = true;
    overlays = [ unstable ];
  };
in
{
  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Install firefox.
  programs.firefox.enable = true;

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  environment.systemPackages = with pkgs; [
    unstable.alacritty
    cups
    vlc
    solaar
    rofi
    rofi-wayland
    eww
    powertop
    tlp
  ];

}
