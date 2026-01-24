# Inject ntfy token to Grafana
# `nix run .#inject-ntfy-token hostname`
{
  pkgs,
  lib,
}:
pkgs.writeShellApplication {
  name = "inject-ntfy-token";
  runtimeInputs = with pkgs; [
    openssh
    coreutils
    openssl
  ];
  text = ''
    # shellcheck source=/dev/null
    source ${lib}

    readonly DOMAIN="nb.krejci.io"
    readonly TOKEN_ENV_PATH="/var/lib/grafana/secrets/ntfy-token-env"
    readonly TOKEN_TXT_PATH="/var/lib/alertmanager/secrets/ntfy-token.txt"

    function create_ntfy_user() {
      local -r target="$1"

      info "Creating ntfy user 'grafana'"
      local -r password=$(openssl rand -base64 32)
      # shellcheck disable=SC2029 # password intentionally expands on client side
      ssh "$target" "printf '%s\n%s\n' '$password' '$password' | sudo ntfy user add --role=admin grafana 2>&1 || true"
    }

    function generate_ntfy_token() {
      local -r target="$1"

      info "Generating ntfy token"
      local token
      token=$(ssh "$target" "sudo ntfy token add grafana" | grep -oP 'token \K[^ ]+')

      if [ -z "$token" ]; then
        error "Failed to generate token"
        exit 1
      fi

      echo -n "$token"
    }

    function write_token_configs() {
      local -r target="$1"
      local -r token="$2"

      info "Creating token configuration"

      # Environment file for Grafana
      inject_secret \
        --target "$target" \
        --path "$TOKEN_ENV_PATH" \
        --content "NTFY_TOKEN=$token"

      # Plain text file for Alertmanager credentials_file
      inject_secret \
        --target "$target" \
        --path "$TOKEN_TXT_PATH" \
        --content "$token"
    }

    function restart_services() {
      local -r target="$1"

      info "Restarting services"
      ssh "$target" "sudo systemctl restart grafana.service 2>/dev/null || echo 'Grafana will start on next deployment'"
      ssh "$target" "sudo systemctl restart alertmanager.service 2>/dev/null || echo 'Alertmanager will start on next deployment'"
    }

    function main() {
      local -r hostname=$(require_and_validate_hostname "$@")
      local -r target="admin@$hostname.$DOMAIN"

      require_ssh_reachable "$target"

      info "Setting up ntfy authentication for $hostname"

      create_ntfy_user "$target"
      local -r token=$(generate_ntfy_token "$target")

      write_token_configs "$target" "$token"
      restart_services "$target"

      info "ntfy token successfully configured for $hostname"
    }

    main "$@"
  '';
}
