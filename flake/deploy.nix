# deploy-rs configuration
{
  inputs,
  config,
  self,
  ...
}: let
  lib = inputs.nixpkgs.lib;
  # Get hosts from the hosts module
  hostsConfig = config.flake.hosts;
  nixosHosts = lib.filterAttrs (_: h: h.kind == "nixos") hostsConfig;

  # Create a deploy node entry
  mkNode = hostName: hostConfig: {
    hostname = "${hostName}.nb.krejci.io";
    sshUser = "admin";
    profiles.system = {
      user = "root";
      path =
        inputs.deploy-rs.lib.${
          if hostConfig.isRpi
          then "aarch64-linux"
          else "x86_64-linux"
        }
        .activate.nixos
        self.nixosConfigurations.${hostName};
    };
  };
in {
  flake.deploy.nodes = lib.mapAttrs mkNode nixosHosts;
}
