# Tokyo Night color palettes as plain attribute sets.
# Importable by both NixOS and home-manager modules.
# Color values from: https://wixdaq.github.io/Tokyo-Night-Website/
# The upstream nix-colors base16 mapping has broken base08/base09/base0A assignments,
# so both palettes are defined manually here.
{
  darkPalette = {
    accent = "7AA2F7"; # semantic accent -- blue for dark variants
    panelBg = "16161E"; # chrome -- sidebar, statusbar, tab bar
    base00 = "1A1B26"; # bg -- night editor background
    base01 = "1F2335"; # lighter bg -- line highlight, status bar
    base02 = "292E42"; # selection -- visual mode highlight
    base03 = "565F89"; # comments -- inline annotations
    base04 = "787C99"; # dark fg -- line numbers, fold markers
    base05 = "A9B1D6"; # default fg -- primary text
    base06 = "C0CAF5"; # light fg -- headings, bold text
    base07 = "D5D6DB"; # lightest fg -- cursor line text
    base08 = "F7768E"; # red -- errors, deletions, diff removed
    base09 = "FF9E64"; # orange -- constants, numbers, booleans
    base0A = "E0AF68"; # yellow -- warnings, search highlight
    base0B = "9ECE6A"; # green -- strings, insertions, diff added
    base0C = "7DCFFF"; # cyan -- types, regex, escape sequences
    base0D = "7AA2F7"; # blue -- functions, methods, links, interactive accent
    base0E = "BB9AF7"; # purple -- keywords, operators, tags
    base0F = "DB4B4B"; # dark red -- deprecated, invalid tokens
  };

  lightPalette = {
    accent = "A8652A"; # semantic accent -- warm orange-brown for light variant
    panelBg = "D0D5E3"; # chrome -- upstream bg_dark for visible bar separation
    base00 = "E1E2E7"; # bg -- day editor background
    base01 = "D5D6DB"; # slightly darker bg -- line highlight, status bar
    base02 = "C4C8DA"; # selection -- visual mode highlight
    base03 = "9699A3"; # comments -- inline annotations
    base04 = "8990A3"; # dark fg -- line numbers, fold markers
    base05 = "343B59"; # default fg -- dark neutral gray for readable UI text
    base06 = "1A1B26"; # darker fg -- headings, bold text
    base07 = "1A1B26"; # darkest fg -- cursor line text
    base08 = "F52A65"; # red -- errors, deletions, diff removed
    base09 = "B15C00"; # orange -- constants, numbers, booleans
    base0A = "8C6C3E"; # yellow -- warnings, search highlight
    base0B = "587539"; # green -- strings, insertions, diff added
    base0C = "007197"; # cyan -- types, regex, escape sequences
    base0D = "2E7DE9"; # blue -- functions, methods, links
    base0E = "9854F1"; # purple -- keywords, operators, tags
    base0F = "C64343"; # dark red -- deprecated, invalid tokens
  };
}
