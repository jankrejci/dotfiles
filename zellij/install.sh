#!/usr/bin/env bash

# Get the script location as it can be run from different place.
script_dir=$(dirname "$(realpath "$0")")

dotfiles_dir=$(dirname "$script_dir")
# shellcheck disable=SC1091
source "$dotfiles_dir/common.sh"

GITHUB_REPO="zellij-org/zellij"
CONFIG_FOLDER="$HOME/.config/zellij"

install_from_binary() {
	msg "    • downloading precompiled binary"
	download_from_github "$GITHUB_REPO"
	package_path=$(find "$TMP_DIR" -name 'zellij*')

	package_name=$(basename "$package_path")
	msg "    • downloaded package $package_name"

	tar -xf "$package_path" -C "$TMP_DIR"
	install_binary "$TMP_DIR/zellij"
	msg "    • installed into $BIN_FOLDER"
}

link_configuration_files() {
	msg "    • linking configuration files"
	mkdir --parents "$CONFIG_FOLDER"
	ln -sf "$script_dir/config.kdl" "$CONFIG_FOLDER"
	rm -rf "$CONFIG_FOLDER/themes"
	ln -sf "$script_dir/themes" "$CONFIG_FOLDER"
	rm -rf "$CONFIG_FOLDER/layouts"
	ln -sf "$script_dir/layouts" "$CONFIG_FOLDER"
}

msg "${BOLD}Zellij installation${NOFORMAT}"
apt_install "fonts-powerline"
install_from_binary
link_configuration_files
msg "${GREEN}    • instalation done${NOFORMAT}"
