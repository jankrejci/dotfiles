{
  pkgs,
  nixos-anywhere,
  ...
}: let
  lib = import ./lib.nix {inherit pkgs;};

  # Helper to import a script with standard arguments
  callScript = path: import path {inherit pkgs lib;};

  # Helper for scripts that need extra arguments
  callScriptWith = args: path: import path ({inherit pkgs lib;} // args);
in {
  add-ssh-key = callScript ./add-ssh-key.nix;
  build-sdcard = callScript ./build-sdcard.nix;
  build-installer = callScript ./build-installer.nix;
  deploy-config = callScript ./deploy-config.nix;
  nixos-install = callScriptWith {inherit nixos-anywhere;} ./nixos-install.nix;
  reenroll-netbird = callScript ./reenroll-netbird.nix;
  inject-borg-passphrase = callScript ./inject-borg-passphrase.nix;

  # Validate ssh-authorized-keys.conf is parseable
  validate-ssh-keys = pkgs.runCommand "validate-ssh-keys" {} ''
    cd ${./..}

    if [ ! -f ssh-authorized-keys.conf ]; then
      echo "ERROR: ssh-authorized-keys.conf not found"
      exit 1
    fi

    # Test parsing: skip comments/empty, extract hostname/user/key
    ${pkgs.gnugrep}/bin/grep -v "^#" ssh-authorized-keys.conf | \
      ${pkgs.gnugrep}/bin/grep -v "^[[:space:]]*$" | \
      while IFS=, read -r host user key; do
        # Trim whitespace
        host=$(echo "$host" | ${pkgs.coreutils}/bin/tr -d ' \t')
        user=$(echo "$user" | ${pkgs.coreutils}/bin/tr -d ' \t')

        if [ -z "$host" ] || [ -z "$user" ] || [ -z "$key" ]; then
          echo "ERROR: Invalid line (missing hostname, user, or key)"
          exit 1
        fi
      done

    echo "ssh-authorized-keys.conf is parseable"
    touch $out
  '';

  # Import Google Keep notes to Memos with preserved timestamps
  # `nix run .#import-keep https://memos.example.com TOKEN ~/Keep`
  import-keep = pkgs.callPackage ../pkgs/import-keep {};

  # Expose the shared library for testing
  inherit lib;

  # Tests for the shared library functions
  script-lib-test =
    pkgs.runCommand "script-lib-test" {
      buildInputs = with pkgs; [
        bash
        nix
        jq
      ];
    } ''
      set -euo pipefail

      # Create a test environment
      export HOME=$(mktemp -d)
      mkdir -p hosts/test-host
      mkdir -p hosts/another-host

      # Source the shared library
      source ${lib}

      echo "Running script library tests..."

      # Test require_hostname function
      test_require_hostname() {
        echo "Testing require_hostname..."

        # Test with no arguments (should fail)
        set +e
        (require_hostname >/dev/null 2>&1)
        local exit_code=$?
        set -e
        if [ $exit_code -ne 1 ]; then
          echo "ERROR: require_hostname should fail with no arguments"
          return 1
        fi

        # Test with arguments (should pass)
        require_hostname "test-host"

        echo "✓ require_hostname tests passed"
      }

      # Run all tests
      test_require_hostname

      echo "All tests passed!"
      touch $out
    '';
}
