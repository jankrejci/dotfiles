#!/usr/bin/env bash

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

cleanup() {
	trap - SIGINT SIGTERM ERR EXIT
	tput cnorm
}

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
	tput civis
	msg -n " "
	while kill -0 "$pid" 2>/dev/null; do
		local i=$(((i + char_width) % ${#spin}))
		printf "%s" "${spin:$i:$char_width}"
		echo -en "\033[1D"
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
Usage: $(basename "${BASH_SOURCE[0]}") [-s]

Install and configures Zellij.
	
Available options:

-s, --source    Install Zellij from source files
-h, --help      Print this help and exit
    --debug     Print script debug info
    --no-color  Print without colors
EOF
	exit
}

parse_params() {
	config_folder="$HOME/.config/zellij"
	build_from_source=false

	while :; do
		case "${1-}" in
		-s | --source) build_from_source=true ;;
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

install_dependencies() {
	read -r -a packages <<<"$@"
	for package in "${packages[@]}"; do
		if ! dpkg -s "$package" &>/dev/null; then
			not_installed_packages+=("$package")
		fi
	done

	if [ -n "${not_installed_packages-}" ]; then
		msg -n "    • installing Ubuntu packages" "${not_installed_packages[@]}"
		sudo apt -y install "${not_installed_packages[@]}" &>/dev/null &
		spinner
	fi
}

install_from_binary() {
	msg -n "    • installing from precompiled binary"
	cargo binstall -y zellij &>/dev/null &
	spinner
}

install_from_source() {
	msg -n "    • compiling from source, it may take a while"
	cargo install --quiet --locked zellij &>/dev/null &
	spinner
}

msg "${BOLD}Zellij installation${NOFORMAT}"

install_dependencies "fonts-powerline"

if [ "$build_from_source" == true ]; then
	install_from_source
else
	install_from_binary
fi

msg "    • linking configuration files"
mkdir --parents "$config_folder"
ln -sf "$script_dir/config.kdl" "$config_folder"
rm -rf "$config_folder/themes"
ln -sf "$script_dir/themes" "$config_folder"
rm -rf "$config_folder/layouts"
ln -sf "$script_dir/layouts" "$config_folder"
