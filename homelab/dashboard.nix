# Homelab dashboard - static landing page
#
# Aggregates dashboard entries from all hosts and generates a static HTML page
# with service links and icons. No backend, nginx serves files directly.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.homelab.dashboard;
  global = config.homelab.global;
  services = config.homelab.services;
  domain = global.domain;
  dashDomain = "${cfg.subdomain}.${domain}";

  # Collect dashboard entries from all nixos hosts
  allConfigs = inputs.self.nixosConfigurations;
  nixosHostNames = lib.attrNames (
    lib.filterAttrs (
      _: host:
        (host.kind or "nixos") == "nixos"
    )
    config.homelab.hosts
  );
  allEntries = lib.flatten (
    map (
      name: allConfigs.${name}.config.homelab.dashboardEntries or []
    )
    nixosHostNames
  );

  # Sort entries alphabetically by name
  sortedEntries = lib.sort (a: b: a.name < b.name) allEntries;

  # Generate an HTML tile for a single dashboard entry
  mkTile = entry: ''
    <a class="tile" href="${entry.url}">
      <img src="icons/${lib.toLower entry.name}.svg" alt="${entry.name}">
      <span>${entry.name}</span>
    </a>
  '';

  htmlContent = ''
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>${domain}</title>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
          background: #1a1a2e;
          color: #e0e0e0;
          min-height: 100vh;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          padding: 2rem 1rem;
        }
        h1 {
          font-size: 2rem;
          font-weight: 600;
          margin-bottom: 3rem;
          color: #8888aa;
        }
        .grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(140px, 160px));
          justify-content: center;
          gap: 1.25rem;
          width: 100%;
          max-width: 720px;
        }
        .tile {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 0.75rem;
          padding: 1.5rem 1rem;
          background: #16213e;
          border-radius: 12px;
          text-decoration: none;
          color: #e0e0e0;
          transition: background 0.2s, transform 0.2s;
        }
        .tile:hover {
          background: #1a2744;
          transform: translateY(-2px);
        }
        .tile img {
          width: 64px;
          height: 64px;
        }
        .tile span {
          font-size: 0.9rem;
          text-align: center;
        }
      </style>
    </head>
    <body>
      <h1>${domain}</h1>
      <div class="grid">
        ${lib.concatStringsSep "\n      " (map mkTile sortedEntries)}
      </div>
    </body>
    </html>
  '';

  htmlFile = pkgs.writeText "dashboard-index.html" htmlContent;

  # Build static site derivation with HTML and icons
  dashboardPage = pkgs.runCommand "homelab-dashboard" {} ''
    mkdir -p $out/icons
    cp ${htmlFile} $out/index.html
    ${lib.concatStringsSep "\n" (map (
        entry: "cp ${entry.icon} $out/icons/${lib.toLower entry.name}.svg"
      )
      allEntries)}
  '';
in {
  options.homelab.dashboard = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable homelab dashboard landing page";
    };

    ip = lib.mkOption {
      type = lib.types.str;
      description = "IP address for nginx to listen on";
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "home";
      description = "Subdomain for the dashboard";
    };
  };

  config = lib.mkIf cfg.enable {
    # Register IP for services dummy interface
    homelab.serviceIPs = [cfg.ip];
    networking.hosts.${cfg.ip} = [dashDomain];

    # Allow HTTPS on VPN interface
    networking.firewall.interfaces."${services.netbird.interface}".allowedTCPPorts = [
      services.https.port
    ];

    # Serve static dashboard files
    services.nginx.virtualHosts.${dashDomain} = {
      listenAddresses = [cfg.ip];
      forceSSL = true;
      useACMEHost = domain;
      root = dashboardPage;
      locations."/" = {
        tryFiles = "$uri $uri/ /index.html";
      };
    };
  };
}
