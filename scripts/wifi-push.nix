# Push the locally stored WiFi networks to a running host's iwd state
# directory over SSH, for a host that was never imaged with them or whose
# networks changed since.
#
# - reads the same secrets/wifi-credentials.age as the SD card image build
# - sends each profile on stdin to a remote `install`, so a passphrase
#   never appears in a command's argv or in a build's Nix store
# - only adds or overwrites profiles; it never removes one that the secret
#   no longer lists, so pruning a stale network stays a manual step
# - usage: nix run .#wifi-push hostname
{
  pkgs,
  lib,
}: let
  iwdProfile = import ../modules/iwd-profile.nix;

  # Render the profile template once, at Nix build time, with the printf
  # conversion `%s` standing in for the passphrase. printf substitutes the
  # passphrase as an argument, never as part of the format string, so a
  # literal `%` or `\` typed into a WiFi password cannot be read back as
  # printf syntax. The only `%` in this rendered text is that placeholder.
  pskFormat = iwdProfile.profile "%s";
in
  pkgs.writeShellApplication {
    name = "wifi-push";
    runtimeInputs = with pkgs; [
      age
      # The sourced lib uses date, basename and cut.
      coreutils
      jq
      # The sourced lib runs nix eval in require_and_validate_hostname.
      nix
      openssh
    ];
    text = ''
      # shellcheck source=/dev/null
      source ${lib}

      readonly DOMAIN="nb.krejci.io"
      readonly IWD_STATE_DIR=${pkgs.lib.escapeShellArg iwdProfile.stateDir}
      readonly IWD_PSK_SUFFIX=${pkgs.lib.escapeShellArg iwdProfile.pskSuffix}
      readonly PSK_FORMAT=${pkgs.lib.escapeShellArg pskFormat}

      function push_profile() {
        local -r target="$1"
        local -r ssid="$2"
        local -r passphrase="$3"

        local -r remote_path="$IWD_STATE_DIR/$ssid$IWD_PSK_SUFFIX"
        local quoted_path
        quoted_path=$(printf '%q' "$remote_path")

        info "Pushing profile for $ssid"
        # Not restarting iwd here is deliberate: this push may itself be
        # running over the link iwd just connected, and a restart would
        # drop it. iwd rereads /var/lib/iwd on its next association, so the
        # new or changed profile takes effect without one.
        #
        # PSK_FORMAT is the fixed template rendered from
        # modules/iwd-profile.nix at build time; the passphrase is only
        # ever a printf argument, never part of the format.
        local rendered
        # shellcheck disable=SC2059 # PSK_FORMAT is the intended format string, not user input
        rendered=$(printf -- "$PSK_FORMAT" "$passphrase")

        # shellcheck disable=SC2029 # quoted_path is pre-escaped and intentionally expands client side
        printf '%s\n' "$rendered" |
          ssh "$target" "sudo install -D -m 600 -o root -g root /dev/stdin $quoted_path" || {
          error "Failed to push profile for $ssid to $target"
          exit 1
        }
      }

      function main() {
        local -r hostname=$(require_and_validate_hostname "$@")
        local -r target="admin@$hostname.$DOMAIN"

        require_ssh_reachable "$target"

        load_wifi_networks

        local ssids
        ssids=$(echo "$WIFI_NETWORKS" | jq -r 'keys[]')

        local ssid
        local passphrase
        while IFS= read -r ssid; do
          passphrase=$(echo "$WIFI_NETWORKS" | jq -r --arg ssid "$ssid" '.[$ssid]')
          push_profile "$target" "$ssid" "$passphrase"
        done <<< "$ssids"

        unset WIFI_NETWORKS
        info "WiFi profiles pushed to $hostname"
      }

      main "$@"
    '';
  }
