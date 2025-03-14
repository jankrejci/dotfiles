#!/usr/bin/env bash

# Install nixos through the bootable USB flash

# Usage
# ./scripts/install.sh rpi4

HOSTNAME="$1"

TARGET="iso.vpn"

ADMIN_KEY_PATH="$HOME/.config/sops/age/keys.txt"

AGE_KEY_FOLDER="var/cache/sops/age"
AGE_KEY_PATH="$AGE_KEY_FOLDER/keys.txt"

SSH_KEY_FOLDER="/etc/secrets/initrd"
SSH_KEY_PATH="$SSH_KEY_FOLDER/ssh_host_ed25519_key"

# Create a temporary directory
temp=$(mktemp -d)

# Function to cleanup temporary directory on exit
cleanup() {
	rm -rf "$temp"
}
trap cleanup EXIT

# Create the directory where sops expects to find the age key
install -d -m755 "$temp/$AGE_KEY_FOLDER"
# Decrypt host's private age key
export SOPS_AGE_KEY_FILE="$ADMIN_KEY_PATH"
# Decrypt your private key from the secrets and copy it to the temporary directory
sops --decrypt --extract '["sops_private_key"]' "hosts/$HOSTNAME/secrets.yaml" >"$temp/$AGE_KEY_PATH"
# Set restricted permissions
chmod 600 "$temp/$AGE_KEY_PATH"

# Create the directory where sshd expects to find the host keys
install -d -m755 "$temp/$SSH_KEY_FOLDER"
# Generate ssh key pair
ssh-keygen -t ed25519 -f "$temp/$SSH_KEY_PATH" -C "initrd" -N ""
# Set restricted permissions
chmod 600 "$temp/$SSH_KEY_PATH"

# Install NixOS to the host system with our secrets
nix run github:nix-community/nixos-anywhere -- \
	--generate-hardware-config nixos-generate-config "hosts/$HOSTNAME/hardware-configuration.nix" \
	--extra-files "$temp" \
	--flake ".#$HOSTNAME" \
	--target-host "root@$TARGET"
