#!/usr/bin/env bash

# Get the script location as it can be run from different place.
script_dir=$(dirname "$(realpath "$0")")
dotfiles_dir=$(dirname "$script_dir")
# shellcheck disable=SC1091
source "$dotfiles_dir/common.sh"

debug "Installing from Ubuntu package"
sudo apt -y install git &>/dev/null

link_configuration_files \
	"config" \

info "Installation done"
