# fwupd-efi with the signed EFI helper pointing at a machine-local signature
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
# This is a function of fwupd-efi rather than an overlay. fwupd compiles the
# helper's location in, so an overlay rebuilt fwupd and every package linking
# it, gnome-software among them, none of which any binary cache holds.
fwupd-efi: let
  signedApp = "/var/lib/fwupd-efi/fwupdx64.efi.signed";
in
  fwupd-efi.overrideAttrs (old: {
    postInstall =
      (old.postInstall or "")
      + ''
        ln -s ${signedApp} $out/libexec/fwupd/efi/fwupdx64.efi.signed
      '';

    passthru = (old.passthru or {}) // {inherit signedApp;};
  })
