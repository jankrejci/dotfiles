#!/usr/bin/env sh

# Get the script location as it can be run from different place.
script_dir=$(dirname "$(realpath "$0")")

# shellcheck disable=SC1091
. "./common.sh"

info "Installing dotfiles"

install_folders="git rust nerdfonts alacritty zellij nushell helix starship"

for folder in $install_folders; do
	cd "$script_dir/$folder" && ./install.sh "$@"
done
