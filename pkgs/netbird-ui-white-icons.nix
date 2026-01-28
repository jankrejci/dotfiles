# Netbird UI overlay for white tray icons
#
# - converts orange icons to white silhouettes
# - matches GNOME symbolic icon style
# - uses imagemagick colorize filter
final: prev: {
  netbird-ui = prev.netbird-ui.overrideAttrs (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ [final.imagemagick];

    # Convert all tray icons to white silhouettes
    postPatch =
      (old.postPatch or "")
      + ''
        for icon in client/ui/assets/netbird-systemtray-*.png; do
          echo "Converting $icon to white"
          # Colorize opaque pixels to white, preserve transparency
          magick "$icon" -fill white -colorize 100 "$icon"
        done
      '';
  });
}
