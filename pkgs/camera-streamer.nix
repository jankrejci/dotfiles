# Build camera-streamer from source with native libcamera support.
# FFmpeg is disabled since nixpkgs doesn't have FFmpeg 5.x.
# MJPEG streaming works fine without FFmpeg, only H264 encoding needs it.
{
  lib,
  stdenv,
  fetchFromGitHub,
  pkg-config,
  xxd,
  libcamera,
  openssl,
  nlohmann_json,
}: let
  version = "0.4.1";
in
  stdenv.mkDerivation {
    pname = "camera-streamer";
    inherit version;

    src = fetchFromGitHub {
      owner = "ayufan";
      repo = "camera-streamer";
      rev = "v${version}";
      hash = "sha256-Gz8NArht3sU9DGzL3geLYfc+ZNt/pLVJca6Q/kiCzmc=";
      fetchSubmodules = true;
    };

    nativeBuildInputs = [
      pkg-config
      xxd
    ];

    buildInputs = [
      libcamera
      openssl
      nlohmann_json
    ];

    # camera-streamer uses plain Makefile, not autotools
    dontConfigure = true;

    # GCC 14 triggers warnings-as-errors on aarch64 due to:
    # - False positive in glibc fortify checks on poll array size
    # - Format string mismatch with size_t on 64-bit systems
    # - Unused result from system() call
    env.NIX_CFLAGS_COMPILE = "-Wno-error=stringop-overflow -Wno-error=format -Wno-error=unused-result";

    # Disable optional features to simplify the build
    makeFlags = [
      "USE_FFMPEG=0"
      "USE_LIBDATACHANNEL=0"
      "USE_RTSP=0"
      "USE_HW_H264=0"
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin
      cp camera-streamer $out/bin/

      runHook postInstall
    '';

    meta = {
      description = "High-performance low-latency camera streamer for Raspberry Pi";
      homepage = "https://github.com/ayufan/camera-streamer";
      license = lib.licenses.gpl3;
      platforms = ["aarch64-linux"];
    };
  }
