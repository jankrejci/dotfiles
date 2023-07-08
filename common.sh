#!/usr/bin/env bash
# Bash executable doesn't have to be always in /bin folder, this command searches PATH for bash
# https://stackoverflow.com/questions/21612980/why-is-usr-bin-env-bash-superior-to-bin-bash

# This template aims to give solid foundation of the shell script.
# Origin of the script is here https://betterdev.blog/minimal-safe-bash-script-template/
# * Be correct.
#     - any script based on this template should be able to pass `shellcheck`
#     - clenaup of resources is done even in failure condition
# * Fail fast, fail safe.
#     - to be correct you neeed to find bugs
#     - if there is some problem say it
# * Run in most environments.
#     - Do not rely on particular environment like Ubuntu
#     - Target architectures are x86_64 and aarch64
#	  - Target plaform is linux, target distros are debian based
#     - It should run on desktop, server and raspberry pi
# * Be standalone.
#     - Do not rely on external dependencies like eg. Python
#     - Reasonable assumption is that the environment is Unix based with bash
# * Show usefull help.
#     - Show how to use the script
#     - If there is problem, describe it
# * Be short.
#     - Target is to be under 300 lines
# * Be fancy.
#     - Show colors to distinguish the message importance
#     - Let the user know something happens there, use spinners

# Fail fast. If command fails, also the script should fail to discover bugs soon.
# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
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

# Workaround to ask for sudo password at the beginning of the script,
# but not to run all commands as root
sudo echo -n
parse_params "$@"
setup_colors

