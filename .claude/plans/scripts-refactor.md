# Scripts Refactor Plan

## Problem

`scripts.nix` is a single large file containing all deployment and utility scripts.
Hard to navigate and edit individual scripts.

## Solution

Split into modular files under `scripts/` directory.

## Structure

```
scripts/
  lib.nix              # Shared functions (writeShellScript, sourceable)
  default.nix          # Thin wrapper, imports and re-exports all scripts
  deploy-config.nix
  build-sdcard.nix
  nixos-install.nix
  reenroll-netbird.nix
  add-ssh-key.nix
  build-installer.nix
```

After secrets migration completes, injection scripts will be removed:
- inject-cloudflare-token.nix
- inject-ntfy-token.nix
- inject-dex-secrets.nix
- inject-borg-passphrase.nix

## lib.nix

Sourceable shell script with shared functions:

```nix
{ pkgs }:
pkgs.writeShellScript "script-lib" ''
  function setup_colors() {
    if [ -t 2 ] && [ -z "''${NO_COLOR:-}" ]; then
      RED=$'\033[0;31m'
      GREEN=$'\033[0;32m'
      ORANGE=$'\033[0;33m'
      BLUE=$'\033[0;34m'
      NC=$'\033[0m'
    else
      RED="" GREEN="" ORANGE="" BLUE="" NC=""
    fi
  }

  function message() { ... }
  function info() { ... }
  function warn() { ... }
  function error() { ... }

  setup_colors

  function require_hostname() { ... }
  function validate_hostname() { ... }
  function require_and_validate_hostname() { ... }
  function require_ssh_reachable() { ... }
''
```

## Script File Pattern

Each script exports a writeShellApplication:

```nix
# scripts/deploy-config.nix
{ pkgs, lib }:
pkgs.writeShellApplication {
  name = "deploy-config";
  runtimeInputs = with pkgs; [ deploy-rs openssh nix ];
  text = ''
    # shellcheck source=/dev/null
    source ${lib}

    function main() {
      # ... script code
    }

    main "$@"
  '';
}
```

## default.nix

Collects all scripts:

```nix
{ pkgs, nixos-anywhere, ... }:
let
  lib = import ./lib.nix { inherit pkgs; };
  callScript = f: import f { inherit pkgs lib; };
  callScriptWith = args: f: import f ({ inherit pkgs lib; } // args);
in {
  add-ssh-key = callScript ./add-ssh-key.nix;
  build-sdcard = callScript ./build-sdcard.nix;
  build-installer = callScript ./build-installer.nix;
  deploy-config = callScript ./deploy-config.nix;
  nixos-install = callScriptWith { inherit nixos-anywhere; } ./nixos-install.nix;
  reenroll-netbird = callScript ./reenroll-netbird.nix;

  # Checks stay inline
  validate-ssh-keys = pkgs.runCommand "validate-ssh-keys" {} ''
    # ... validation code
  '';

  script-lib-test = pkgs.runCommand "script-lib-test" {
    buildInputs = with pkgs; [ bash nix jq ];
  } ''
    source ${lib}
    # ... test code
  '';

  inherit lib;
  import-keep = pkgs.callPackage ../pkgs/import-keep {};
}
```

## Flake Update

Update `flake/packages.nix`:

```nix
# before
scripts = import ../scripts.nix { ... };

# after
scripts = import ../scripts { ... };
```

Delete old `scripts.nix` after migration.

## Benefits

- Each script in its own file, easier to read and edit
- Shared lib in dedicated file
- Shellcheck still runs via writeShellApplication
- runtimeInputs still available
- `nix run .#deploy-config` etc. still work unchanged
