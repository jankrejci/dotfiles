{lib, ...}: let
  domain = "x.nb";
  dnsPort = 5354;

  # CNAME records for services pointing to hosts
  # Format: service.x.nb -> host.x.nb
  # Netbird DNS resolves the host.x.nb to actual IP
  serviceAliases = {
    "immich.${domain}" = "thinkcenter.${domain}";
  };

  # Generate CNAME entries for dnsmasq
  # Format: alias,target (key "cname" is added by NixOS)
  cnameEntries = lib.mapAttrsToList (alias: target: "${alias},${target}") serviceAliases;
in {
  # Allow custom DNS port on VPN interface
  networking.firewall.interfaces."nb-homelab".allowedTCPPorts = [dnsPort];
  networking.firewall.interfaces."nb-homelab".allowedUDPPorts = [dnsPort];

  services.dnsmasq = {
    enable = true;
    settings = {
      # Only listen on Netbird interface
      interface = "nb-homelab";
      port = dnsPort;

      # Don't read /etc/resolv.conf or /etc/hosts
      no-resolv = true;
      no-hosts = true;

      # CNAME aliases for services -> hosts
      # dnsmasq returns CNAME, Netbird DNS resolves the actual IP
      cname = cnameEntries;

      # Return REFUSED for unknown queries (allows Netbird to try other nameservers)
      # Don't claim authority over the entire domain

      # Cache settings
      cache-size = 150;

      # Logging (optional, can be removed)
      log-queries = false;
    };
  };

  # Ensure Netbird is running (for interface to exist)
  systemd.services.dnsmasq = {
    after = ["netbird-homelab.service"];
    wants = ["netbird-homelab.service"];
  };
}
