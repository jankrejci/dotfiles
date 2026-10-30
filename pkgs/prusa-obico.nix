# Prusa MK3S to Obico bridge
# Speaks G-code over the TCP serial bridge to the printer and the Obico agent
# protocol to the cloud, reporting status and snapshots and taking commands.
{
  rustPlatform,
  lib,
}:
rustPlatform.buildRustPackage {
  pname = "prusa-obico";
  version = "0.1.0";

  src = ./prusa-obico;

  cargoHash = "sha256-Qg83EPZHjACXpbpwyRy8H/7pPVyGgB6ojb+cDZd7eI8=";

  meta = {
    description = "Bridge between a Prusa MK3S serial link and the Obico cloud";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "prusa-obico";
  };
}
