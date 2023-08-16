#!/usr/bin/env bash

# Get the script location as it can be run from different place.
script_dir=$(dirname "$(realpath "$0")")

dotfiles_dir=$(dirname "$script_dir")
# shellcheck disable=SC1091
source "$dotfiles_dir/common.sh"

github_repo="zellij-org/zellij"
config_folder="$HOME/.config/zellij"
cargo_bin="$HOME/.cargo/bin"

install_from_binary() {
	msg "    • downloading precompiled binary"
	download_from_github "$github_repo"
	package_path=$(find "$TMP_DIR" -name 'zellij*')

	package_name=$(basename "$package_path")
	msg "    • downloaded package $package_name"

	tar -xf "$package_path" -C "$TMP_DIR"
	mv "$TMP_DIR/zellij" "$cargo_bin"
	msg "    • installed into $cargo_bin"
}

link_configuration_files() {
	msg "    • linking configuration files"
	mkdir --parents "$config_folder"
	ln -sf "$script_dir/config.kdl" "$config_folder"
	rm -rf "$config_folder/themes"
	ln -sf "$script_dir/themes" "$config_folder"
	rm -rf "$config_folder/layouts"
	ln -sf "$script_dir/layouts" "$config_folder"
}

msg "${BOLD}Zellij installation${NOFORMAT}"
apt_install "fonts-powerline"
install_from_binary
link_configuration_files
msg "${GREEN}    • instalation done${NOFORMAT}"
