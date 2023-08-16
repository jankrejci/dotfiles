#!/usr/bin/env bash

set -Eeuo pipefail

# Cleanup all temporary resources.
trap cleanup SIGINT SIGTERM ERR EXIT

cleanup() {
	trap - SIGINT SIGTERM ERR EXIT
	tput cnorm
	# Script cleanup here
}

die() {
	local msg=$1
	# Default exit status 1
	local code=${2-1}
	msg "$msg"
	exit "$code"
}

# shellcheck disable=SC2034
setup_colors() {
	if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
		NOFORMAT='\033[0m'
		RED='\033[0;31m'
		GREEN='\033[0;32m'
		ORANGE='\033[0;33m'
		BLUE='\033[0;34m'
		PURPLE='\033[0;35m'
		CYAN='\033[0;36m'
		YELLOW='\033[1;33m'
		BOLD='\033[1m'
	else
		NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW='' BOLD=''
	fi
}

spinner() {
	# Make sure we use non-unicode character type locale
	local LC_CTYPE=C
	# Process Id of the previous running command
	local pid=$!

	local spin='⣾⣽⣻⢿⡿⣟⣯⣷'
	local char_width=3

	local i=0
	# cursor invisible
	tput civis;	msg -n " ";
	while kill -0 "$pid" 2>/dev/null; do
		local i=$(((i + char_width) % ${#spin}))
		printf "%s" "${spin:$i:$char_width}"
		# Move cursor back
		echo -en "\033[1D"
		sleep .1
	done
	# Erase spinner and print new line. It is expected that the spinner
	# is shown at the end of message
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

Available options:

-s, --source    Build Helix from source
-h, --help      Print this help and exit
    --debug     Print script debug info
    --no-color  Print without colors
EOF
	exit
}

# shellcheck disable=SC2034
parse_params() {
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

# Install Ubuntu packages, but check if it is not already installed first.
# It possibly allows to run the script even without sudo privileges.
apt_install() {
	read -r -a packages <<<"$@"
	for package in "${packages[@]}"; do
		if ! dpkg -s "$package" &>/dev/null; then
			not_installed_packages+=("$package")
		fi
	done

	if [ -n "${not_installed_packages-}" ]; then
		msg -n "    • installing packages through apt" "${not_installed_packages[@]}"
		sudo apt -y install "${not_installed_packages[@]}" &>/dev/null &
		spinner
	fi
}

# Workaround to ask for sudo password at the beginning of the script,
# but not to run all commands as root
sudo echo -n
parse_params "$@"
setup_colors

