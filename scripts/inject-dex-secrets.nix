# Inject Dex OAuth client secrets for all services
# `nix run .#inject-dex-secrets hostname`
#
# Creates secrets for Dex and downstream services. Immich config is handled
# declaratively in immich.nix via systemd preStart, not here.
{
  pkgs,
  lib,
}:
pkgs.writeShellApplication {
  name = "inject-dex-secrets";
  runtimeInputs = with pkgs; [openssh openssl];
  text = ''
    # shellcheck source=/dev/null
    source ${lib}

    readonly PEER_DOMAIN="nb.krejci.io"
    readonly DEX_ISSUER="https://dex.krejci.io"
    readonly DEX_SECRETS_DIR="/var/lib/dex/secrets"
    readonly DEX_GOOGLE_OAUTH_FILE="$DEX_SECRETS_DIR/google-oauth"
    readonly GRAFANA_SECRETS_DIR="/var/lib/grafana/secrets"
    readonly DEX_CLIENTS=(grafana immich memos jellyfin)

    function require_google_oauth() {
      local -r target="$1"
      # Variables expand locally before SSH to build remote command
      # shellcheck disable=SC2029
      ssh "$target" "[ -f $DEX_GOOGLE_OAUTH_FILE ]" && return
      warn "Create $DEX_GOOGLE_OAUTH_FILE with GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET first"
      exit 1
    }

    function generate_client_secrets() {
      local -r target="$1"
      for client in "''${DEX_CLIENTS[@]}"; do
        local secret_file="$DEX_SECRETS_DIR/$client-client-secret"
        # Variables expand locally before SSH to build remote command
        # shellcheck disable=SC2029
        ssh "$target" "[ -f $secret_file ]" && { info "$client secret exists"; continue; }
        # Each service owns its secret so preStart can read it
        inject_secret \
          --target "$target" \
          --path "$secret_file" \
          --content "$(openssl rand -hex 32)" \
          --owner "$client:$client"
      done
    }

    function configure_grafana() {
      local -r target="$1"
      local -r dex_grafana_secret="$DEX_SECRETS_DIR/grafana-client-secret"
      local -r grafana_dex_secret="$GRAFANA_SECRETS_DIR/dex-client-secret"
      # Variables expand locally before SSH to build remote command
      # shellcheck disable=SC2029
      ssh "$target" "sudo mkdir -p $GRAFANA_SECRETS_DIR && \
        sudo cp $dex_grafana_secret $grafana_dex_secret && \
        sudo chown grafana:grafana $grafana_dex_secret"
      info "Grafana secret configured"
    }

    function print_memos_instructions() {
      local -r target="$1"
      local -r dex_memos_secret="$DEX_SECRETS_DIR/memos-client-secret"
      # Variables expand locally before SSH to build remote command
      # shellcheck disable=SC2029
      local -r secret=$(ssh "$target" "sudo cat $dex_memos_secret")
      info "Memos: configure manually in Settings → SSO"
      echo "  Client ID: memos"
      echo "  Client Secret: $secret"
      echo "  Issuer URL: $DEX_ISSUER"
    }

    function print_jellyfin_instructions() {
      local -r target="$1"
      local -r dex_jellyfin_secret="$DEX_SECRETS_DIR/jellyfin-client-secret"
      # Variables expand locally before SSH to build remote command
      # shellcheck disable=SC2029
      local -r secret=$(ssh "$target" "sudo cat $dex_jellyfin_secret")
      info "Jellyfin: install SSO plugin, then configure in Dashboard → Plugins → SSO"
      echo "  Provider Name: dex"
      echo "  OID Endpoint: $DEX_ISSUER"
      echo "  Client ID: jellyfin"
      echo "  Client Secret: $secret"
      echo "  Enabled: checked"
    }

    function main() {
      local -r hostname=$(require_and_validate_hostname "$@")
      local -r target="admin@$hostname.$PEER_DOMAIN"
      require_ssh_reachable "$target"

      require_google_oauth "$target"
      generate_client_secrets "$target"
      configure_grafana "$target"
      print_memos_instructions "$target"
      print_jellyfin_instructions "$target"
    }

    main "$@"
  '';
}
