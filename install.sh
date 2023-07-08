#!/usr/bin/env bash

set -Eeuo pipefail

trap cleanup SIGINT SIGTERM ERR EXIT

cleanup() {
	trap - SIGINT SIGTERM ERR EXIT
	tput cnorm
	# Script cleanup here
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

msg() {
	echo >&2 -e "$@"
}

usage() {
	cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}")

Batch install oo the environment.

Available options:

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


sudo echo -n
parse_params "$@"
setup_colors

msg "${BOLD}Installing dotfiles\n${NOFORMAT}"

install_dependencies "fontconfig"

install_folders=("git" "rust" "nerdfonts" "alacritty" "zellij" "nushell" "helix" "starship")
for folder in "${install_folders[@]}"; do
	cd "$script_dir/$folder" && ./install.sh "$@"
done
