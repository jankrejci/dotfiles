#!/usr/bin/env bash

HOSTNAME="$1"

ADMIN_KEY_PATH="$HOME/.config/sops/age/keys.txt"
TARGET_FOLDER="var/cache/sops/age"
TARGET_PATH="$TARGET_FOLDER/keys.txt"

# Create a temporary directory
temp=$(mktemp -d)

# Function to cleanup temporary directory on exit
cleanup() {
	rm -rf "$temp"
}
trap cleanup EXIT

# Create the directory where sshd expects to find the host keys
install -d -m755 "$temp/$TARGET_FOLDER"

# Decrypt host's private age key
export SOPS_AGE_KEY_FILE="$ADMIN_KEY_PATH"
# Decrypt your private key from the secrets and copy it to the temporary directory
sops --decrypt --extract '["sops_private_key"]' "hosts/$HOSTNAME/secrets.yaml" >"$temp/$TARGET_PATH"

# Set the correct permissions
chmod 600 "$temp/$TARGET_PATH"

# Install NixOS to the host system with our secrets
nix run github:nix-community/nixos-anywhere -- \
	--generate-hardware-config nixos-generate-config "hosts/$HOSTNAME/hardware-configuration.nix" \
	--extra-files "$temp" \
	--flake ".#$HOSTNAME" \
	--target-host "root@iso.vpn"
