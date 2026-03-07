# Shared oauth2-proxy SSO gateway
#
# Single oauth2-proxy instance shared by all services on this host that lack
# native OIDC support. Each service registers itself as a virtualHost in
# services.oauth2-proxy.nginx.virtualHosts and gets transparent auth_request
# protection.
#
# Authentication flow:
#   User hits protected service -> nginx auth_request -> oauth2-proxy checks
#   cookie -> if no session, redirect to Dex -> user authenticates -> cookie
#   set on .<domain> -> redirect back to original URL.
#
# Cookie domain .<domain> gives cross-subdomain SSO: one Dex login covers
# all protected services on this host.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.sso-proxy;
  global = config.homelab.global;
  domain = global.domain;
  dexDomain = "${config.homelab.dex.subdomain}.${domain}";
  callbackDomain = "${cfg.callbackSubdomain}.${domain}";
in {
  options.homelab.sso-proxy = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable shared oauth2-proxy SSO gateway";
    };

    port = lib.mkOption {
      type = lib.types.port;
      description = "Port for oauth2-proxy listener";
    };

    callbackSubdomain = lib.mkOption {
      type = lib.types.str;
      description = "Subdomain of the virtualHost that hosts /oauth2/ callback paths";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homelab.dex.enable;
        message = "homelab.sso-proxy requires homelab.dex.enable = true";
      }
    ];

    # Register OIDC client with Dex for SSO
    homelab.dex.clients = [
      {
        id = "sso-proxy";
        name = "SSO Proxy";
        redirectURIs = ["https://${callbackDomain}/oauth2/callback"];
        secretRekeyFile = ../secrets/dex-sso-proxy-secret.age;
      }
    ];

    # oauth2-proxy environment file with client secret and cookie secret
    age.secrets.sso-proxy-env = {
      rekeyFile = ../secrets/oauth2-proxy-thinkcenter-env.age;
      owner = "oauth2-proxy";
    };

    services.oauth2-proxy = {
      enable = true;
      httpAddress = "http://127.0.0.1:${toString cfg.port}";
      provider = "oidc";
      clientID = "sso-proxy";
      keyFile = config.age.secrets.sso-proxy-env.path;
      redirectURL = "https://${callbackDomain}/oauth2/callback";
      oidcIssuerUrl = "https://${dexDomain}";
      reverseProxy = true;
      setXauthrequest = true;
      email.domains = ["*"];
      scope = "openid email profile";
      cookie = {
        secure = true;
        domain = ".${domain}";
      };
      extraConfig = {
        skip-provider-button = true;
        code-challenge-method = "S256";
      };
      nginx.domain = callbackDomain;
    };

    # Health check
    homelab.healthChecks = [
      {
        name = "SSO Proxy";
        script = pkgs.writeShellApplication {
          name = "health-check-sso-proxy";
          runtimeInputs = [pkgs.systemd];
          text = ''
            systemctl is-active --quiet oauth2-proxy.service
          '';
        };
        timeout = 10;
      }
    ];

    homelab.alerts.sso-proxy = [
      {
        alert = "SsoProxyDown";
        expr = ''node_systemd_unit_state{name="oauth2-proxy.service",state="active",host="${config.homelab.host.hostName}"} == 0'';
        labels = {
          severity = "critical";
          host = config.homelab.host.hostName;
          type = "service";
        };
        annotations.summary = "SSO proxy is down, all SSO-protected services are inaccessible";
      }
    ];
  };
}
