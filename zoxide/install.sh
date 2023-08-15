#!/usr/bin/env bash

# Get the script location as it can be run from different places
script_dir=$(dirname "$(realpath "$0")")
dotfiles_dir=$(dirname "$script_dir")
. "$dotfiles_dir/common.sh"

GITHUB_REPO="ajeetdsouza/zoxide"
BINARY_NAME="zoxide"

install_from_github "$GITHUB_REPO" "$BINARY_NAME"

info "Installation done"
