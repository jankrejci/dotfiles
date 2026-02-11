# Shared NixOS module builders for hosts.nix and images.nix
#
# Both nixosConfigurations and image builders need the same base modules
# and host module assembly logic. This avoids duplicating that code.
{
  inputs,
  lib,
  hosts,
  global,
  services,
}: {
  # Common base modules for all hosts
  baseModules = [
    inputs.home-manager.nixosModules.home-manager
    inputs.disko.nixosModules.disko
    inputs.nix-flatpak.nixosModules.nix-flatpak
    inputs.agenix.nixosModules.default
    inputs.agenix-rekey.nixosModules.default
    # agenix-rekey configuration
    ({config, ...}: let
      pubkey = config.homelab.host.hostPubkey or null;
    in {
      age.rekey = {
        # Master identity private key on deploy machines only
        masterIdentities = ["~/.age/master.txt"];
        # Both master keys can decrypt all secrets independently
        extraEncryptionPubkeys = [
          "age1ctfxxgl7laucsyca94ucxe6cdnq59e480pfjukmtjq25m4r874zsf8kvmf" # framework
          "age190jnchn50yr6w428un7sz62n7pwd7q9n8h3r8wpu3830kus97fcsnk0ftq" # t14
        ];
        storageMode = "local";
        localStorageDir = ../secrets/rekeyed + "/${config.networking.hostName}";
        # Host pubkey from host definition in hosts attrset
        hostPubkey = lib.mkIf (pubkey != null) pubkey;
        # No hardware key plugins needed, use plain age only
        agePlugins = [];
      };
    })
    ../modules # Base system modules
    ../homelab # Service modules with enable pattern
    ../users/admin.nix
  ];

  # Create modules list for a host
  mkModulesList = {
    hostName,
    host,
    additionalModules ? [],
  }: let
    hostConfigFile = ../hosts/${hostName}.nix;
    hasHostConfig = builtins.pathExists hostConfigFile;
  in
    [
      # Inject shared homelab configuration
      ({...}: {
        # Current host metadata for modules that need device, swapSize, etc.
        # Excludes homelab key - use config.homelab.X for service config instead.
        homelab.host = (builtins.removeAttrs host ["homelab"]) // {hostName = host.hostName or hostName;};
        # All hosts for cross-host references like wireguard peers
        homelab.hosts = hosts;
        # Global config: domain, peerDomain
        homelab.global = global;
        # Shared service config: https.port, metrics.port, netbird.*
        homelab.services = services;
      })
      # Inject host-specific homelab config directly into NixOS module system.
      # The attrset merges with option definitions from ../homelab/*.nix modules.
      ({...}: {homelab = host.homelab or {};})
    ]
    ++ lib.optional hasHostConfig hostConfigFile
    ++ host.extraModules or []
    ++ additionalModules;
}
