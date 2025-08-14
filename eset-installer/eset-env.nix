{pkgs ? import <nixpkgs> {}}:
pkgs.buildFHSEnv {
  name = "eset-installer-env";
  targetPkgs = pkgs:
    with pkgs; [
      openssl
      glibc
      gcc
      zlib
      coreutils
      bash
      pam
      shadow
      util-linux
      wget
      curl
      systemd
      gnused
      gawk
      gnutar
      gzip
      procps
      psmisc
      findutils
      which
      file
      ncurses
      expat
      libxml2
      libselinux
      openssl
      cacert
    ];
  runScript = "bash";
}
