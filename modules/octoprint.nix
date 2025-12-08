{
  config,
  lib,
  pkgs,
  ...
}: let
  services = config.serviceConfig;
  domain = "krejci.io";
  serverDomain = "${services.octoprint.subdomain}.${domain}";
  serviceIP = config.hostConfig.self.serviceHosts.octoprint;
  httpsPort = 443;

  # Obico plugin for AI-powered print failure detection
  # https://github.com/TheSpaghettiDetective/OctoPrint-Obico
  mkObicoPlugin = ps:
    ps.buildPythonPackage rec {
      pname = "octoprint-plugin-obico";
      version = "2.5.6";
      format = "setuptools";
      src = pkgs.fetchFromGitHub {
        owner = "TheSpaghettiDetective";
        repo = "OctoPrint-Obico";
        rev = version;
        hash = "sha256-Q593zv5CWX7Tmun/ddq2cF/jg0hIIitSxS1VnyCFcac=";
      };
      propagatedBuildInputs = with ps; [
        octoprint
        backoff
        sentry-sdk
        bson
        distro
      ];
      doCheck = false;
    };
in {
  # Allow HTTPS on VPN interface
  networking.firewall.interfaces."${services.octoprint.interface}".allowedTCPPorts = [httpsPort];

  services.octoprint = {
    enable = true;
    # Listen on localhost only, accessed via nginx proxy
    host = "127.0.0.1";
    port = services.octoprint.port;
    plugins = ps: [(mkObicoPlugin ps)];
  };

  # Wait for services interface before binding
  systemd.services.nginx.after = ["sys-subsystem-net-devices-services.device"];

  services.nginx = {
    enable = true;
    virtualHosts.${serverDomain} = {
      listenAddresses = [serviceIP];
      forceSSL = true;
      useACMEHost = "${domain}";
      # Only allow access from Netbird VPN network
      extraConfig = ''
        allow 100.76.0.0/16;
        deny all;
      '';
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString services.octoprint.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };
}
