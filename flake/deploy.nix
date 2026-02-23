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

  # Overlay that provides deploy-rs lib using cached nixpkgs binaries.
  # Without this, deploy-rs builds from source via QEMU for aarch64.
  deployRsOverlay = final: _prev: let
    pkgs = import inputs.nixpkgs {system = final.stdenv.hostPlatform.system;};
  in {
    deploy-rs = {
      inherit (pkgs) deploy-rs;
      lib = (inputs.deploy-rs.overlays.default final _prev).deploy-rs.lib;
    };
  };

  # Get deploy-rs lib for a target system
  deployLib = system:
    (import inputs.nixpkgs {
      inherit system;
      overlays = [deployRsOverlay];
    })
    .deploy-rs
    .lib;

  # Create a deploy node entry
  mkNode = hostName: host: {
    hostname = "${hostName}.${global.peerDomain}";
    sshUser = "admin";
    # VPN-based deploys need extra time for nftables reload and SSH reconnection
    profiles.system = {
      user = "root";
      path = (deployLib host.system).activate.nixos self.nixosConfigurations.${hostName};
      confirmTimeout = 60;
    };
  };
in {
  flake.deploy.nodes = lib.mapAttrs mkNode nixosHosts;
}
