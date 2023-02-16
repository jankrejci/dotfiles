#!/usr/bin/env bash
set -Eeuo pipefail

trap cleanup SIGINT SIGTERM ERR EXIT

cleanup() {
	trap - SIGINT SIGTERM ERR EXIT
	tput cnorm
	# rm -rf "$TMP_DIR"
}

die() {
	local msg=$1
	local code=${2-1}
	msg "$msg"
	exit "$code"
}

setup_colors() {
	if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
		NOFORMAT='\033[0m'
		RED='\033[0;31m'
		BOLD='\033[1m'
	else
		NOFORMAT='' RED='' BOLD=''
	fi
}

spinner() {
	local LC_CTYPE=C
	local pid=$!

	local spin='⣾⣽⣻⢿⡿⣟⣯⣷'
	local char_width=3

	local i=0
	tput civis
	msg -n " "
	while kill -0 "$pid" 2>/dev/null; do
		local i=$(((i + char_width) % ${#spin}))
		printf "%s" "${spin:$i:$char_width}"
		msg -n "\033[1D"
		sleep .1
	done
	tput cnorm
	msg " "
	wait "$pid"
	return $?
}

msg() {
	echo >&2 -e "$@"
}

usage() {
	cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}")

Installs Rust through rustup and cargo_binstall.

Available options:

-f, --flag      Some flag description
-p, --param     Some param description
-h, --help      Print this help and exit
    --debug     Print script debug info
    --no-color  Print without colors
EOF
	exit
}

parse_params() {
	while :; do
		case "${1-}" in
		-h | --help) usage ;;
		--debug) set -x ;;
		--no-color) NO_COLOR=1 ;;
		-?*) die "Unknown option: $1" ;;
		*) break ;;
		esac
		shift
	done
	return 0
}

sudo echo -n
parse_params "$@"
setup_colors

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
