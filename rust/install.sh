#!/usr/bin/env bash

# Get the script location as it can be run from different place.
script_dir=$(dirname "$(realpath "$0")")

dotfiles_dir=$(dirname "$script_dir")
# shellcheck disable=SC1091
source "$dotfiles_dir/common.sh"

install_rustup() {
	rustup_init="$TMP_DIR/rustup-init.sh"
	curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs >"$rustup_init"
	chmod +x "$rustup_init"

	msg -n "    • installing Rust"
	"$rustup_init" -y &>/dev/null &
	spinner

	PATH=$PATH:$HOME/.cargo/bin/
}

install_cargo_binstall() {
	CARGO_BIN="$HOME/.cargo/bin"

	detected_platform=$(uname -m)
	msg "    • detected platform $detected_platform"
	case ${detected_platform} in
	"x86_64")
		package_file="cargo-binstall-x86_64-unknown-linux-musl.tgz"
		;;
	"aarch64")
		package_file="cargo-binstall-aarch64-unknown-linux-musl.tgz"
		;;
	*)
		die "${RED}unknown platform${NOFORMAT}"
		;;
	esac

	BASE_ADDRESS="https://github.com/cargo-bins/cargo-binstall/releases/latest/download"
	package_link="$BASE_ADDRESS/$package_file"
	curl -LJsSf "$package_link" >"$TMP_DIR/$package_file"
	tar zxf "$TMP_DIR/$package_file" --directory "$TMP_DIR"
	mv "$TMP_DIR/cargo-binstall" "$CARGO_BIN"
}

msg "${BOLD}Installing Rust${NOFORMAT}"

TMP_DIR="/tmp/dotfiles"
mkdir --parents $TMP_DIR

msg "    • installing Rustup"
install_rustup

msg "    • installing cargo-binstall from binary"
install_cargo_binstall
