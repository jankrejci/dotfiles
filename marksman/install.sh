#!/usr/bin/env bash

# Get the script location as it can be run from different places
script_dir=$(dirname "$(realpath "$0")")
dotfiles_dir=$(dirname "$script_dir")
. "$dotfiles_dir/common.sh"

GITHUB_REPO="artempyanykh/marksman"
BINARY_NAME="marksman"

# Override detected architecture
case "$ARCH" in
  "x86_64") ARCH="x64";;
  "aarch64") ARCH="arm64";;
  *) die "Platform is not supported";;
esac
debug "Architecture overriden to $ARCH"

package_path=$(download_from_github "$GITHUB_REPO")
binary_path="$TMP_DIR/$BINARY_NAME"
mv "$package_path" "$binary_path"
install_binary "$binary_path" "$BINARY_NAME"

info "Installation done"
