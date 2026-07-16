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

  # These modules provide Hyprland-specific user services such as hypridle,
  # waybar, wpaperd and swayosd. Bind them to hyprland-session.target instead
  # of the default graphical-session.target so they only start under Hyprland.
  # Under GNOME, which shares graphical-session.target, hypridle would otherwise
  # crash-loop because Mutter does not expose ext-idle-notifier-v1.
  wayland.systemd.target = "hyprland-session.target";
}
