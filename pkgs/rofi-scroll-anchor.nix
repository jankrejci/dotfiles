# Rofi overlay to replace center-anchored scrolling with margin-based scrolling
#
# scroll-method = 1 pins the selected item to the viewport center, which causes
# the list to jump on every keystroke. This replaces the midpoint algorithm with
# a margin-based approach where the cursor moves freely and the list only scrolls
# when the selection enters a one-item margin at either edge.
#
# Must override rofi-unwrapped because rofi is a wrapper that does not build
# from source. The wrapper automatically picks up the patched unwrapped package.
final: prev: {
  rofi-unwrapped = prev.rofi-unwrapped.overrideAttrs (old: {
    patches = (old.patches or []) ++ [./rofi-scroll-anchor.patch];
  });
}
