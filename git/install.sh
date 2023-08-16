#!/usr/bin/env bash

# Get the script location as it can be run from different place.
script_dir=$(dirname "$(realpath "$0")")

dotfiles_dir=$(dirname "$script_dir")
# shellcheck disable=SC1091
source "$dotfiles_dir/common.sh"

CONFIG_FOLDER="$HOME/.config/git"

msg "${BOLD}Git installation${NOFORMAT}"

msg "    • installing from Ubuntu package"
sudo apt -y install git &>/dev/null

msg "    • linking configuration files"
mkdir --parents "$CONFIG_FOLDER"
ln -sf "$script_dir/config" "$CONFIG_FOLDER"

msg "${GREEN}    • instalation done${NOFORMAT}"
