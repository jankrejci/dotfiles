# Netbird UI overlay: recolor tray icons to match panel text.
#
# Netbird bundles orange PNG tray icons that clash with the GNOME Shell
# and waybar panel styling. This overlay converts them at build time
# using the panel foreground color from our palette.
{color}: final: prev: {
  unstable =
    prev.unstable
    // {
      netbird-ui = prev.unstable.netbird-ui.overrideAttrs (old: {
        nativeBuildInputs = old.nativeBuildInputs ++ [final.imagemagick];

        # Colorize opaque pixels to the panel text color, preserve transparency.
        postPatch =
          (old.postPatch or "")
          + ''
            for icon in client/ui/assets/netbird-systemtray-*.png; do
              magick "$icon" -fill '#${color}' -colorize 100 "$icon"
            done
          '';
      });
    };
}
