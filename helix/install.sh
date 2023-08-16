#!/usr/bin/env bash

# Get the script location as it can be run from different place.
script_dir=$(dirname "$(realpath "$0")")

dotfiles_dir=$(dirname "$script_dir")
# shellcheck disable=SC1091
. "$dotfiles_dir/common.sh"

GITHUB_REPO="helix-editor/helix"
CONFIG_FOLDER="$HOME/.config/helix"
BINARY_NAME="hx"

install_from_binary(){
	install_from_github "$GITHUB_REPO" "$BINARY_NAME"
	
	debug "Copying helix runtimes"
	mkdir --parents "$CONFIG_FOLDER"
	rsync -a "$extracted_package/runtime" "$CONFIG_FOLDER/"
}

install_additional_components() {
	debug "Installing additional components"

	debug "Installing Rust LSP (rust-analyzer)"
	rustup -q component add rust-analyzer >/dev/null 2>&1

	debug "Installing TOML LSP (taplo-cli)"
	cargo-binstall -y taplo-cli > /dev/null

	debug "Installing Bash LSP (bash-language-server)"
	# TODO install npm 16 first
	sudo npm install --silent -g bash-language-server >/dev/null 2>&1

	debug "Installing Python LSP"
	pip install python-lsp-server >/dev/null 2>&1

	debug "Installing Shfmt"
	curl -sS https://webi.sh/shfmt | sh >/dev/null 2>&1

}

apt_install "shellcheck"
install_from_binary
install_additional_components
link_configuration_files \
	"config.toml" \
	"languages.toml" \
	"themes"
info "Installation done"
