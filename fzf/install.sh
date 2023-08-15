#!/usr/bin/env bash

# Get the script location as it can be run from different places
script_dir=$(dirname "$(realpath "$0")")
dotfiles_dir=$(dirname "$script_dir")
. "$dotfiles_dir/common.sh"

GITHUB_REPO="junegunn/fzf"
BINARY_NAME="fzf"

# Override detected architecture
case "$ARCH" in
  "x86_64") ARCH="amd64";;
  "aarch64") ARCH="arm64";;
  *) die "Platform is not supported";;
esac
debug "Architecture overriden to $ARCH"

install_from_github "$GITHUB_REPO" "$BINARY_NAME"

info "Installation done"

