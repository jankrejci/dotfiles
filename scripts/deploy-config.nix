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

    # A magic rollback has been seen to end with deploy exiting zero, so only the
    # target can prove that the new generation stayed. The rollback switches the
    # profile back first, and a running activate-rs means it can still happen.
    function verify_deployment() {
      local -r hostname="$1"
      local -r target="$2"
      local -r expected="$3"
      shift 3

      local ssh_opts=()
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --dry-activate | --test)
            warn "Skipping verification, this mode leaves the profile unchanged"
            return 0
            ;;
          --ssh-opts=*) read -ra ssh_opts <<<"''${1#--ssh-opts=}" ;;
          --ssh-opts)
            read -ra ssh_opts <<<"''${2:-}"
            shift
            ;;
        esac
        shift
      done

      local state
      state=$(ssh -o ConnectTimeout=15 -o BatchMode=yes "''${ssh_opts[@]}" "$target" \
        "readlink -f /nix/var/nix/profiles/system; pgrep -f '[a]ctivate-rs' >/dev/null && echo pending; true") || {
        error "Cannot verify $hostname, its state over SSH is unknown"
        exit 1
      }

      [[ "$state" != *pending* ]] || {
        error "Activation is still running on $hostname, it can still roll back"
        exit 1
      }
      [ "$state" = "$expected" ] || {
        error "$hostname is not on the new generation, the deploy rolled back or was interrupted"
        exit 1
      }
    }

    function main() {
      local -r hostname=$(require_and_validate_hostname "$@")
      local -r target="admin@$hostname.$DOMAIN"
      shift

      require_ssh_reachable "$target"

      # The path depends on the state of the tree, so it is read before the deploy
      # to keep an edit made during a long deploy from failing the verification.
      # Declared apart from the assignment, because local would mask a failed
      # eval and the verification would then blame a rollback.
      local expected
      expected=$(nix eval --raw ".#deploy.nodes.$hostname.profiles.system.path.outPath")

      info "Deploying to $hostname"

      # Use '-- -L' to print full build logs instead of progress bar
      deploy \
        --skip-checks \
        ".#$hostname" "$@"

      verify_deployment "$hostname" "$target" "$expected" "$@"

      info "Deployment complete"
    }

    main "$@"
  '';
}
