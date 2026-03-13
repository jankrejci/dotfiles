# Hyprland window manager and desktop components
#
# Split into submodules for maintainability. Each submodule manages its own
# theme toggle registration and nix-managed variant files.
{...}: {
  imports = [
    ./core.nix
    ./waybar.nix
    ./rofi.nix
    ./idle-lock.nix
    ./notifications.nix
    ./osd.nix
    ./wallpaper.nix
    ./theme.nix
  ];
}
