#!/usr/bin/env bash

# Get the script location as it can be run from different place.
script_dir=$(dirname "$(realpath "$0")")
dotfiles_dir=$(dirname "$script_dir")
# shellcheck disable=SC1091
. "$dotfiles_dir/common.sh"

GITHUB_REPO="zellij-org/zellij"

install_from_binary() {
	debug "Downloading precompiled binary"
	download_from_github "$GITHUB_REPO"
	package_path=$(find "$TMP_DIR" -name 'zellij*')

	package_name=$(basename "$package_path")
	debug "Downloaded package $package_name"

	tar -xf "$package_path" -C "$TMP_DIR"
	install_binary "$TMP_DIR/zellij"
	debug "Installed into $BIN_DIR"
}

debug "Installation started"
apt_install "fonts-powerline"
install_from_binary
link_configuration_files \
	"config.kdl" \
	"themes" \
	"layouts"
debug "Installation done"
