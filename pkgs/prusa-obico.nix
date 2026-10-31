# Prusa MK3S to Obico bridge
# Speaks G-code over the TCP serial bridge to the printer and the Obico agent
# protocol to the cloud, reporting status and snapshots and taking commands.
# The package build runs the crate's tests. The clippy lints that deny unwrap,
# indexing and panics are enforced by the prusa-obico-clippy check in
# flake/packages.nix, not by this derivation.
{
  rustPlatform,
  lib,
  makeWrapper,
  ffmpeg-headless,
}: let
  manifest = (lib.importTOML ./prusa-obico/Cargo.toml).package;
in
  rustPlatform.buildRustPackage {
    pname = "prusa-obico";
    inherit (manifest) version;

    src = ./prusa-obico;

    cargoLock.lockFile = ./prusa-obico/Cargo.lock;

    nativeBuildInputs = [makeWrapper];

    # The bridge cuts snapshots from the H.264 stream by running ffmpeg, so
    # the wrapper puts it on PATH and the CLI default resolves.
    postInstall = ''
      wrapProgram $out/bin/prusa-obico \
        --prefix PATH : ${lib.makeBinPath [ffmpeg-headless]}
    '';

    meta = {
      description = "Bridge between a Prusa MK3S serial link and the Obico cloud";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
      mainProgram = "prusa-obico";
    };
  }
