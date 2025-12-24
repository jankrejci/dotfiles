# Netbird groups and policies configuration
# Synced to API via: nix run .#sync-netbird-config
{...}: let
  config = {
    groups = {
      servers = {};
      desktops = {};
      raspberry-pi = {};
      monitoring = {};
    };
    policies = {
      admin-ssh = {
        description = "Allow SSH from desktops to servers";
        rules = [
          {
            name = "ssh";
            sources = ["desktops"];
            destinations = ["servers" "raspberry-pi"];
            protocol = "tcp";
            ports = ["22"];
          }
        ];
      };
      monitoring = {
        description = "Prometheus metrics scraping";
        rules = [
          {
            name = "metrics";
            sources = ["monitoring"];
            destinations = ["servers" "raspberry-pi"];
            protocol = "tcp";
            ports = ["9999"];
          }
        ];
      };
    };
  };

  # Sync script builder - takes pkgs and lib from scripts.nix
  mkSyncScript = {
    pkgs,
    lib,
  }:
    pkgs.writeShellApplication {
      name = "sync-netbird-config";
      runtimeInputs = with pkgs; [coreutils curl jq nix];
      text = ''
        # shellcheck source=/dev/null
        source ${lib}

        readonly API="https://api.netbird.io/api"

        DRY_RUN=false
        DELETE=false
        YES=false

        while [ $# -gt 0 ]; do
          case "$1" in
            --dry-run) DRY_RUN=true ;;
            --delete) DELETE=true ;;
            --yes) YES=true ;;
            *) error "Unknown option: $1"; exit 1 ;;
          esac
          shift
        done

        # Netbird API request with authentication
        function api() {
          local -r method="$1" endpoint="$2"
          shift 2
          curl -sf -X "$method" "$API$endpoint" \
            -H "Authorization: Token $NETBIRD_API_TOKEN" \
            -H "Content-Type: application/json" "$@"
        }

        # Convert policy from Nix format to API format, resolving group names to IDs
        function policy_to_json() {
          local -r name="$1"
          echo "$DESIRED" | jq --arg name "$name" --argjson lookup "$LOOKUP" '
            .policies[$name] | {
              name: $name,
              description: (.description // ""),
              enabled: (.enabled // true),
              rules: [.rules[] | {
                name,
                description: (.description // ""),
                enabled: (.enabled // true),
                action: (.action // "accept"),
                bidirectional: (.bidirectional // false),
                protocol: (.protocol // "all"),
                ports: (.ports // []),
                sources: [.sources[] as $s | $lookup[$s]],
                destinations: [.destinations[] as $d | $lookup[$d]]
              }]
            }'
        }

        function fetch_state() {
          info "Fetching current state from Netbird API..."
          GROUPS=$(api GET /groups)
          POLICIES=$(api GET /policies)
          LOOKUP=$(echo "$GROUPS" | jq 'map({(.name): .id}) | add // {}')

          info "Reading desired state from flake..."
          DESIRED=$(nix eval .#netbird --json)
        }

        function compute_diff() {
          local current_groups desired_groups current_policies desired_policies

          current_groups=$(echo "$GROUPS" | jq -r '.[].name' | sort)
          desired_groups=$(echo "$DESIRED" | jq -r '.groups | keys[]' | sort)
          current_policies=$(echo "$POLICIES" | jq -r '.[].name' | sort)
          desired_policies=$(echo "$DESIRED" | jq -r '.policies | keys[]' | sort)

          GROUPS_CREATE=$(comm -23 <(echo "$desired_groups") <(echo "$current_groups"))
          GROUPS_EXTRA=$(comm -13 <(echo "$desired_groups") <(echo "$current_groups") | grep -v "^All$" || true)
          POLICIES_CREATE=$(comm -23 <(echo "$desired_policies") <(echo "$current_policies"))
          POLICIES_UPDATE=$(comm -12 <(echo "$desired_policies") <(echo "$current_policies"))
          POLICIES_EXTRA=$(comm -13 <(echo "$desired_policies") <(echo "$current_policies"))
        }

        function show_plan() {
          echo ""
          echo "=== Changes ==="

          [ -n "$GROUPS_CREATE" ] && echo -e "Groups to create:\n$(echo "$GROUPS_CREATE" | sed 's/^/  + /')"
          [ -n "$POLICIES_CREATE" ] && echo -e "Policies to create:\n$(echo "$POLICIES_CREATE" | sed 's/^/  + /')"
          [ -n "$POLICIES_UPDATE" ] && echo -e "Policies to update:\n$(echo "$POLICIES_UPDATE" | sed 's/^/  ~ /')"
          [ -n "$GROUPS_EXTRA" ] && echo -e "Extra groups (--delete to remove):\n$(echo "$GROUPS_EXTRA" | sed 's/^/  ? /')"
          [ -n "$POLICIES_EXTRA" ] && echo -e "Extra policies (--delete to remove):\n$(echo "$POLICIES_EXTRA" | sed 's/^/  ? /')"

          [ -z "$GROUPS_CREATE" ] && [ -z "$POLICIES_CREATE" ] && [ -z "$POLICIES_UPDATE" ] && {
            info "Already in sync"
            exit 0
          }
        }

        function apply_changes() {
          # Create groups first so policies can reference them
          for name in $GROUPS_CREATE; do
            local result id
            result=$(api POST /groups -d "{\"name\":\"$name\",\"peers\":[]}")
            id=$(echo "$result" | jq -r '.id')
            LOOKUP=$(echo "$LOOKUP" | jq --arg n "$name" --arg i "$id" '. + {($n): $i}')
            info "Created group: $name"
          done

          for name in $POLICIES_CREATE; do
            api POST /policies -d "$(policy_to_json "$name")" >/dev/null
            info "Created policy: $name"
          done

          for name in $POLICIES_UPDATE; do
            local id
            id=$(echo "$POLICIES" | jq -r --arg n "$name" '.[] | select(.name==$n) | .id')
            api PUT "/policies/$id" -d "$(policy_to_json "$name")" >/dev/null
            info "Updated policy: $name"
          done

          [ "$DELETE" != true ] && return

          # Delete policies before groups since policies reference groups
          for name in $POLICIES_EXTRA; do
            local id
            id=$(echo "$POLICIES" | jq -r --arg n "$name" '.[] | select(.name==$n) | .id')
            api DELETE "/policies/$id"
            info "Deleted policy: $name"
          done

          for name in $GROUPS_EXTRA; do
            local id
            id=$(echo "$GROUPS" | jq -r --arg n "$name" '.[] | select(.name==$n) | .id')
            api DELETE "/groups/$id"
            info "Deleted group: $name"
          done
        }

        function main() {
          require_netbird_token
          fetch_state
          compute_diff
          show_plan

          [ "$DRY_RUN" = true ] && { info "Dry run, no changes made"; exit 0; }

          if [ "$YES" = false ]; then
            read -rp "Apply changes? [y/N] " response
            [[ "$response" =~ ^[yY]$ ]] || { info "Aborted"; exit 0; }
          fi

          apply_changes
          info "Sync complete"
        }

        main
      '';
    };
in {
  flake.netbird = config;
  flake.netbirdSyncScript = mkSyncScript;
}
