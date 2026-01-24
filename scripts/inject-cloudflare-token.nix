# Inject Cloudflare API token to remote host for ACME certificates
# `nix run .#inject-cloudflare-token hostname`
{
  pkgs,
  lib,
}:
pkgs.writeShellApplication {
  name = "inject-cloudflare-token";
  runtimeInputs = with pkgs; [
    openssh
  ];
  text = ''
    # shellcheck source=/dev/null
    source ${lib}

    readonly DOMAIN="krejci.io"
    readonly PEER_DOMAIN="nb.krejci.io"
    readonly TOKEN_PATH="/var/lib/acme/cloudflare-api-token"

    function main() {
      local -r hostname=$(require_and_validate_hostname "$@")
      local -r target="admin@$hostname.$PEER_DOMAIN"

      require_ssh_reachable "$target"

      info "Injecting Cloudflare token to $hostname"

      local -r token=$(ask_for_token "Cloudflare API token")
      local -r token_content=$(concat \
        "CLOUDFLARE_DNS_API_TOKEN=$token" \
        "CF_ZONE_API_TOKEN=$token"
      )

      inject_secret \
        --target "$target" \
        --path "$TOKEN_PATH" \
        --content "$token_content"

      info "Cloudflare token successfully injected to $hostname"

      info "Restarting ACME service to acquire certificate"
      # shellcheck disable=SC2029 # DOMAIN intentionally expands on client side
      ssh "$target" "sudo systemctl start acme-$DOMAIN.service"

      info "Certificate acquisition initiated. Check status with: systemctl status acme-$DOMAIN.service"
    }

    main "$@"
  '';
}
