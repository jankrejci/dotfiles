#!/usr/bin/env bash

# Build nixos iso or sdcard image and burn it to the target

# Usage
# ./scripts/build.sh rpi4

HOSTNAME="$1"

# Inject wireguard keys into the image
export LOAD_KEYS=1

# Impure is needed for key injection
nix build ".#image.$HOSTNAME" --impure
