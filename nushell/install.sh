#!/usr/bin/env bash

# Get the script location as it can be run from different place.
script_dir=$(dirname "$(realpath "$0")")

dotfiles_dir=$(dirname "$script_dir")
# shellcheck disable=SC1091
. "$dotfiles_dir/common.sh"

GITHUB_REPO="nushell/nushell"
BINARY_NAME="nu"

# TODO install zoxide and fzf as separate tools
apt_install "zoxide fzf"

package_path=$(download_from_github "$GITHUB_REPO")
extracted_package=$(extract_package "$package_path")
install_binary "$extracted_package" "$BINARY_NAME"

link_configuration_files \
	"env.nu" \
    "config.nu" \
	"git-completions.nu" \
	"zellij-completions.nu" \
	"cargo-completions.nu"

info "Installation done"
