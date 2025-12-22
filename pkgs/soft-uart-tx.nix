# Software UART TX for Raspberry Pi GPIO
# Bit-bangs UART output via libgpiod for when hardware TX is dead.
{
  rustPlatform,
  lib,
  pkg-config,
  libgpiod,
}:
rustPlatform.buildRustPackage {
  pname = "soft-uart-tx";
  version = "1.0.0";

  src = ./soft-uart-tx;

  cargoHash = "sha256-7s3cCXR3PZK5Mw9dTDfOPBcZ3Ris99h2IogMWUKDNIo=";

  nativeBuildInputs = [pkg-config];
  buildInputs = [libgpiod];

  meta = {
    description = "Software UART TX via GPIO bit-banging";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "soft-uart-tx";
  };
}
