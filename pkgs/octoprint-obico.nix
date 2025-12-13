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
  octoprint,
  backoff,
  sentry-sdk,
  bson,
  distro,
}:
buildPythonPackage rec {
  pname = "octoprint-plugin-obico";
  version = "2.5.6";
  format = "setuptools";

  src = fetchFromGitHub {
    owner = "TheSpaghettiDetective";
    repo = "OctoPrint-Obico";
    rev = version;
    hash = "sha256-Q593zv5CWX7Tmun/ddq2cF/jg0hIIitSxS1VnyCFcac=";
  };

  propagatedBuildInputs = [
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
