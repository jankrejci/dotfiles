#!/usr/bin/env bash

# Get the script location as it can be run from different place.
script_dir=$(dirname "$(realpath "$0")")

# shellcheck disable=SC1091
. "./common.sh"

install_folders=" 
	git
	rust
	nerdfonts
	alacritty
	zellij
	nushell
	zoxide
	fzf
	fd
	bat
	helix
	marksman
	starship
"

for folder in $install_folders; do
	cd "$script_dir/$folder" && ./install.sh "$@"
done

info "All packages installed succesfully"
