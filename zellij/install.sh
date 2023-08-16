#!/usr/bin/env bash

# Get the script location as it can be run from different place.
script_dir=$(dirname "$(realpath "$0")")

dotfiles_dir=$(dirname "$script_dir")
# shellcheck disable=SC1091
source "$dotfiles_dir/common.sh"

config_folder="$HOME/.config/zellij"

install_from_binary() {
	msg -n "    • installing from precompiled binary"
	cargo binstall -y zellij &>/dev/null &
	spinner
}

msg "${BOLD}Zellij installation${NOFORMAT}"

apt_install "fonts-powerline"

install_from_binary

msg "    • linking configuration files"
mkdir --parents "$config_folder"
ln -sf "$script_dir/config.kdl" "$config_folder"
rm -rf "$config_folder/themes"
ln -sf "$script_dir/themes" "$config_folder"
rm -rf "$config_folder/layouts"
ln -sf "$script_dir/layouts" "$config_folder"
