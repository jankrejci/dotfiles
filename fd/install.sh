#!/usr/bin/env bash

# Get the script location as it can be run from different place.
script_dir=$(dirname "$(realpath "$0")")
dotfiles_dir=$(dirname "$script_dir")
# shellcheck disable=SC1091
. "$dotfiles_dir/common.sh"

GITHUB_REPO="sharkdp/fd"
BINARY_NAME="fd"

install_from_github "$GITHUB_REPO" "$BINARY_NAME"

info "Installation done"


