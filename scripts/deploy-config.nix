# Deploy changes remotely. It is expected that the host
# is running the NixOS and is accessible over network.
# `nix run .#deploy-config hostname`
{
  pkgs,
  lib,
}:
pkgs.writeShellApplication {
  name = "deploy-config";
  runtimeInputs = with pkgs; [
    deploy-rs
    openssh
    nix
  ];
  text = ''
    # shellcheck source=/dev/null
    source ${lib}

    readonly DOMAIN="nb.krejci.io"

    function main() {
      local -r hostname=$(require_and_validate_hostname "$@")
      local -r target="admin@$hostname.$DOMAIN"
      shift

      require_ssh_reachable "$target"

      info "Deploying to $hostname"

      deploy \
        --skip-checks \
        ".#$hostname" "$@"

      info "Deployment complete"
    }

    main "$@"
  '';
}
