# Inject Borg passphrase to both server and client
# `nix run .#inject-borg-passphrase <server-host> <client-host>`
{
  pkgs,
  lib,
}:
pkgs.writeShellApplication {
  name = "inject-borg-passphrase";
  runtimeInputs = with pkgs; [
    openssh
  ];
  text = ''
    # shellcheck source=/dev/null
    source ${lib}

    readonly DOMAIN="nb.krejci.io"
    readonly REPO_PATH="/var/lib/borg-repos/immich"

    function init_repository() {
      local -r server_target="$1"
      local -r passphrase="$2"

      # Client-side expansion intended - passphrase must not leak to logs
      # shellcheck disable=SC2029
      ssh "$server_target" \
        "export BORG_PASSPHRASE='$passphrase' && \
         sudo -E borg init --encryption=repokey-blake2 $REPO_PATH"
    }

    function main() {
      if [ $# -ne 2 ]; then
        error "Usage: inject-borg-passphrase <server-host> <client-host>"
        info "Examples:"
        info "  inject-borg-passphrase vpsfree thinkcenter  # remote backup"
        info "  inject-borg-passphrase thinkcenter thinkcenter  # local backup"
        exit 1
      fi

      local -r server_host="$1"
      local -r client_host="$2"

      local backup_type="remote"
      [ "$server_host" = "$client_host" ] && backup_type="local"

      local -r passphrase=$(ask_for_token "Borg $backup_type passphrase")
      local -r server_target="admin@$server_host.$DOMAIN"
      local -r client_target="admin@$client_host.$DOMAIN"

      require_ssh_reachable "$server_target"
      require_ssh_reachable "$client_target"

      # Check if repository already exists
      info "Checking repository on $server_host"
      local repo_exists=false
      # shellcheck disable=SC2029 # REPO_PATH intentionally expands on client side
      ssh "$server_target" "[ -f $REPO_PATH/config ]" && repo_exists=true

      if [ "$repo_exists" = false ]; then
        init_repository "$server_target" "$passphrase"
        info "Repository initialized"
      fi

      info "Injecting passphrase to $client_host"
      inject_secret \
        --target "$client_target" \
        --path "/root/secrets/borg-passphrase-$backup_type" \
        --content "$passphrase"

      info "Done"
    }

    main "$@"
  '';
}
