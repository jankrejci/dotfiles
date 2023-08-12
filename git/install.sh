#!/usr/bin/env bash

# Get the script location as it can be run from different place.
script_dir=$(dirname "$(realpath "$0")")

dotfiles_dir=$(dirname "$script_dir")
# shellcheck disable=SC1091
source "$dotfiles_dir/common.sh"

CONFIG_FOLDER="$HOME/.config/git"

info "Installation started"

debug "Installing from Ubuntu package"
sudo apt -y install git &>/dev/null

debug "Linking configuration files"
mkdir --parents "$CONFIG_FOLDER"
ln -sf "$script_dir/config" "$CONFIG_FOLDER"

debug "Installation done"
