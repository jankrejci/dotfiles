# OctoPrint plugin for Prometheus metrics export
# https://github.com/tg44/OctoPrint-Prometheus-Exporter
{
  lib,
  fetchFromGitHub,
  buildPythonPackage,
  octoprint,
  prometheus-client,
}:
buildPythonPackage rec {
  pname = "octoprint-plugin-prometheus-exporter";
  version = "0.2.3";
  format = "setuptools";

  src = fetchFromGitHub {
    owner = "tg44";
    repo = "OctoPrint-Prometheus-Exporter";
    rev = version;
    hash = "sha256-pw5JKMWQNAkFkUADR2ue6R4FOmFIeapw2k5FLqJ6NQg=";
  };

  propagatedBuildInputs = [
    octoprint
    prometheus-client
  ];

  doCheck = false;

  meta = {
    description = "OctoPrint plugin for Prometheus metrics export";
    homepage = "https://github.com/tg44/OctoPrint-Prometheus-Exporter";
    license = lib.licenses.mit;
  };
}
