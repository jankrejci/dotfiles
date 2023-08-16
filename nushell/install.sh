#!/usr/bin/env bash

set -Eeuo pipefail

trap cleanup SIGINT SIGTERM ERR EXIT

cleanup() {
	trap - SIGINT SIGTERM ERR EXIT
	tput cnorm
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

die() {
	local msg=$1
	local code=${2-1}
	msg "$msg"
	exit "$code"
}

setup_colors() {
	if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
		NOFORMAT='\033[0m' BOLD='\033[1m'
	else
		NOFORMAT='' BOLD=''
	fi
}

spinner() {
	local LC_CTYPE=C
	local pid=$!

	local spin='⣾⣽⣻⢿⡿⣟⣯⣷'
	local char_width=3

	local i=0
	tput civis;	msg -n " ";
	while kill -0 "$pid" 2>/dev/null; do
		local i=$(((i + char_width) % ${#spin}))
		printf "%s" "${spin:$i:$char_width}"
		# Move cursor back
		echo -en "\033[1D"
		sleep .1
	done
	tput cnorm;	msg " ";
	wait "$pid"
	return $?
}

msg() {
	echo >&2 -e "$@"
}

usage() {
	cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") 

Installs NuShell.

Available options:

-h, --help      Print this help and exit
    --debug     Print script debug info
    --no-color  Print without colors
EOF
	exit
}

parse_params() {
	build_from_source=false
	cargo_bin="$HOME/.cargo/bin"
	config_folder="$HOME/.config/nushell"
	nushell_version="0.82.0"

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
}

install_dependencies() {
	read -r -a packages <<<"$@"
	for package in "${packages[@]}"; do
		if ! dpkg -s "$package" &>/dev/null; then
			not_installed_packages+=("$package")
		fi
	done

	if [ -n "${not_installed_packages-}" ]; then
		msg -n "    • installing Ubuntu packages" "${not_installed_packages[@]}"
		sudo apt -y install "${not_installed_packages[@]}" &>/dev/null & spinner
	fi
}

link_configuration_files() {
	msg "    • linking configuration files"
	read -r -a configs <<<"$@"
	mkdir --parents "$config_folder"
	for config_file in "${configs[@]}"; do
		ln -sf "$script_dir/$config_file" "$config_folder"
	done
}

sudo echo -n
setup_colors
parse_params "$@"

cargo_install () {
	msg -n "    • installing through cargo, it may take a while"
	cargo install nu --features=dataframe &>/dev/null &	spinner
}

install_from_binary(){
	BASE_ADDRESS="https://github.com/nushell/nushell/releases/download"
	package_name="nu-$nushell_version-$detected_platform-unknown-linux-gnu"
	package_file="$package_name.tar.gz"
	package_link="$BASE_ADDRESS/$nushell_version/$package_file"

	msg "    • installing version $nushell_version from binary"

	curl -LJsSf "$package_link" >"$TMP_DIR/$package_file"
	tar xf "$TMP_DIR/$package_file" --directory "$TMP_DIR"

	mv "$TMP_DIR/$package_name/nu" "$cargo_bin"
}

msg "${BOLD}NuShell installation${NOFORMAT}"

TMP_DIR="/tmp/dotfiles"
mkdir --parents "$TMP_DIR"

install_dependencies "pkg-config libssl-dev"

detected_platform=$(uname -m)
msg "    • detected platform $detected_platform"

if [ "$build_from_source" == true ]; then
	cargo_install
else
	install_from_binary
fi

link_configuration_files "env.nu config.nu"
