{pkgs, ...}:
pkgs.writeShellApplication {
  name = "deploy-config";
  runtimeInputs = with pkgs; [
    deploy-rs
  ];
  text = ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Display usage information
    if [ $# -lt 1 ]; then
      echo "Usage: deploy HOSTNAME"
    fi

    readonly hostname="$1"
    shift

    # Run deploy-rs
    echo "Deploying to $hostname..."
    # TODO get rid of skip checks

    deploy \
      --skip-checks \
      ".#$hostname" "$@"
  '';
}
