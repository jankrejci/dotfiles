#!/usr/bin/env bash

# Get the script location as it can be run from different place.
script_dir=$(dirname "$(realpath "$0")")
dotfiles_dir=$(dirname "$script_dir")
# shellcheck disable=SC1091
. "$dotfiles_dir/common.sh"

GITHUB_REPO="zellij-org/zellij"
BINARY_NAME="zellij"

apt_install "fonts-powerline"

package_path=$(download_from_github "$GITHUB_REPO")
extracted_package=$(extract_package "$package_path")
install_binary "$extracted_package" "$BINARY_NAME"

link_configuration_files \
	"config.kdl" \
	"themes" \
	"layouts"

info "Installation done"
