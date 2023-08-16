#!/usr/bin/env bash

# Get the script location as it can be run from different place.
script_dir=$(dirname "$(realpath "$0")")

dotfiles_dir=$(dirname "$script_dir")
# shellcheck disable=SC1091
. "$dotfiles_dir/common.sh"

GITHUB_REPO="nushell/nushell"
CONFIG_FOLDER="$HOME/.config/nushell"

install_from_binary() {
	download_from_github "$GITHUB_REPO"
	package_path=$(find "$TMP_DIR" -name 'nu*')

	package_name=$(basename "$package_path")
	debug "Downloaded package $package_name"
	tar -xf "$package_path" -C "$TMP_DIR"

	nu_folder=$(find "$TMP_DIR" -name 'nu*' -type d)
	install_binary "$nu_folder/nu"
	debug "Installed into $BIN_FOLDER"
}

link_configuration_files() {
	debug "Linking configuration files"
	configs="$*"
	mkdir --parents "$CONFIG_FOLDER"
	for config_file in $configs; do
		ln -sf "$script_dir/$config_file" "$CONFIG_FOLDER"
	done
}

info "Installation started"
# TODO install zoxide and fzf as separate tools
apt_install "zoxide fzf"
install_from_binary
link_configuration_files \
	"env.nu" \
    "config.nu" \
	"git-completions.nu" \
	"zellij-completions.nu" \
	"cargo-completions.nu"
debug "Installation done"
