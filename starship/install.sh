#!/usr/bin/env bash

# Get the script location as it can be run from different places
script_dir=$(dirname "$(realpath "$0")")
dotfiles_dir=$(dirname "$script_dir")
. "$dotfiles_dir/common.sh"

GITHUB_REPO="starship/starship"

package_path=$(download_from_github "$GITHUB_REPO")
extracted_package=$(extract_package "$package_path")
install_binary "$extracted_package"

debug "Linking configuration file"
ln -sf "$script_dir/startship.toml" "$HOME/.config/"

info "Installation done"
