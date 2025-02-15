{
  description = "Generate sops configuration file";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs }:
    let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      lib = pkgs.lib;

      homeDir = builtins.getEnv "HOME";
      adminKeyFilePath = builtins.toFile "admin-keys.txt" (builtins.readFile "${homeDir}/.config/sops/age/keys.txt");

      keys = import ./keys.nix;

      creationRuleForHost = host: {
        path_regex = "hosts/${host}/secrets.yaml";
        key_groups = [{
          age = (lib.attrValues keys.admin) ++ [ keys.hosts.${host} ];
        }];
      };

      hostRules = map creationRuleForHost (lib.attrNames keys.hosts);

      creationRules = hostRules ++ [{
        path_regex = "secrets.yaml";
        key_groups = [{
          age = (lib.attrValues keys.admin);
        }];
      }];

      sopsConfig = {
        keys = {
          users = lib.mapAttrsToList
            (name: key: "${key}")
            keys.admin;
          hosts = lib.mapAttrsToList
            (name: key: "${key}")
            keys.hosts;
        };
        creation_rules = creationRules;
      };

      yamlText = lib.generators.toYAML { } sopsConfig;
    in
    {
      packages.x86_64-linux = {
        config = pkgs.writeShellApplication {
          name = "generate-sops-config";
          runtimeInputs = with pkgs; [ coreutils ];
          text = ''
            printf '${yamlText}' > .sops.yaml
            chmod 644 .sops.yaml
            echo ".sops.yaml has been generated in the current directory."
          '';
        };
        host = pkgs.writeShellApplication {
          name = "generate-secrets";
          runtimeInputs = with pkgs; [ sops yq ];
          text = ''
            #!/usr/bin/env bash
            export SOPS_AGE_KEY_FILE="${adminKeyFilePath}"

            HOSTNAME=$1
            SECRETS_FILE="./secrets.yaml"
            TARGET_DIR="./hosts/$HOSTNAME"
            TARGET_FILE="$TARGET_DIR/secrets.yaml"

            if [ -z "$HOSTNAME" ]; then echo "Usage: nix run .#host <hostname>"; exit 1; fi
            if [ ! -f "$SECRETS_FILE" ]; then echo "$SECRETS_FILE not found"; exit 1; fi

            COMMON_KEYS=$(sops --decrypt "$SECRETS_FILE" | yq ".common" -)
            HOST_KEYS=$(sops --decrypt "$SECRETS_FILE" | yq ".hosts.$HOSTNAME" -)

            mkdir -p "$TARGET_DIR"
            rm -f "$TARGET_FILE"
            echo "$HOST_KEYS" | yq -r 'to_entries | .[] | .key + ": " + .value' - >> "$TARGET_FILE"
            echo "$COMMON_KEYS" | yq -r 'to_entries | .[] | .key + ": " + .value' - >> "$TARGET_FILE"

            sops --encrypt --input-type yaml --output-type yaml "$TARGET_FILE" > "$TARGET_FILE.tmp" && mv "$TARGET_FILE.tmp" "$TARGET_FILE"
            chmod 600 "$TARGET_FILE"
            echo "Generated encrypted secrets for host '$HOSTNAME' at $TARGET_FILE"
          '';
        };
      };
    };
}
