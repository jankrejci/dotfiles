# deploy-rs configuration
{
  inputs,
  config,
  self,
  ...
}: let
  lib = inputs.nixpkgs.lib;
  hosts = config.flake.hosts;
  global = config.flake.global;
  nixosHosts = lib.filterAttrs (_: h: (h.kind or "nixos") == "nixos") hosts;

  # Create a deploy node entry
  mkNode = hostName: host: {
    hostname = "${hostName}.${global.peerDomain}";
    sshUser = "admin";
    profiles.system = {
      user = "root";
      path =
        inputs.deploy-rs.lib.${
          if host.isRpi or false
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
