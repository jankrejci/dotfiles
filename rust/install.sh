#!/usr/bin/env bash

# Get the script location as it can be run from different place.
script_dir=$(dirname "$(realpath "$0")")

dotfiles_dir=$(dirname "$script_dir")
# shellcheck disable=SC1091
source "$dotfiles_dir/common.sh"

CARGO_BIN="$HOME/.cargo/bin"

install_rustup() {
	debug "Installing Rustup"
	rustup_init="$TMP_DIR/rustup-init.sh"
	curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs >"$rustup_init"
	chmod +x "$rustup_init"

	debug "Installing Rust"
	"$rustup_init" -y &>/dev/null

	PATH="$PATH:$CARGO_BIN"
}

install_rustup
debug "Installation done"
