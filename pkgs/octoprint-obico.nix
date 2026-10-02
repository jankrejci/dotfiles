# Obico plugin for AI-powered print failure detection
# https://github.com/TheSpaghettiDetective/OctoPrint-Obico
#
# WebRTC streaming requires ffmpeg and janus-gateway patches but caused
# system crashes on RPi Zero 2 W due to CPU load. Snapshot-only mode
# works without any patches and is sufficient for AI failure detection.
{
  lib,
  fetchFromGitHub,
  buildPythonPackage,
  setuptools,
  octoprint,
  backoff,
  sentry-sdk,
  bson,
  distro,
}:
buildPythonPackage rec {
  pname = "octoprint-plugin-obico";
  version = "2.7.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "TheSpaghettiDetective";
    repo = "OctoPrint-Obico";
    rev = version;
    hash = "sha256-dkBnrnyw153+z3cj0/h5E/onZropi1K1vtI5lgp88rQ=";
  };

  build-system = [setuptools];

  dependencies = [
    octoprint
    backoff
    sentry-sdk
    bson
    distro
  ];

  doCheck = false;

  meta = {
    description = "OctoPrint plugin for AI-powered print failure detection";
    homepage = "https://www.obico.io/";
    license = lib.licenses.agpl3Only;
  };
}
