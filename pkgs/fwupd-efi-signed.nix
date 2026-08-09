# fwupd-efi overlay: point the signed EFI helper at a machine-local signature
#
# With secure boot enabled, fwupd sources its capsule helper from
# fwupdx64.efi.signed next to the unsigned binary and refuses every capsule
# update when that file is missing. Distributions ship one signed by their own
# key through shim, which does not apply here: secure boot runs on sbctl keys
# generated on each machine, and that private key must never enter the store.
#
# So the store entry becomes a symlink into /var/lib, and the sign-fwupd-efi
# service in modules/notebook.nix fills it with a real signature made from the
# unsigned binary in this same output. The path is exposed through passthru so
# the service and the symlink cannot drift apart.
#
# The x64 helper name is spelled out rather than derived from the platform. Only
# flake/packages.nix applies this overlay, and its pkgs reach nixosSystem solely
# through the x86_64-linux mkSystem branch in flake/hosts.nix. RPi hosts build
# from the nixos-raspberrypi nixpkgs with their own overlay list, so no aarch64
# configuration can ever evaluate this.
let
  signedApp = "/var/lib/fwupd-efi/fwupdx64.efi.signed";
in
  final: prev: {
    fwupd-efi = prev.fwupd-efi.overrideAttrs (old: {
      postInstall =
        (old.postInstall or "")
        + ''
          ln -s ${signedApp} $out/libexec/fwupd/efi/fwupdx64.efi.signed
        '';

      passthru = (old.passthru or {}) // {inherit signedApp;};
    });
  }
