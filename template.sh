#!/usr/bin/env bash

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

usage() {
	cat <<EOF
Usage: $(
		basename "${BASH_SOURCE[0]}"
	) [-f] -p param_value arg1 [arg2...]

Script description here.

Available options:

-f, --flag      Some flag description
-p, --param     Some param description
-h, --help      Print this help and exit
    --debug     Print script debug info
    --no-color  Print without colors
EOF
	exit
}

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

function spinner() {
	# Make sure we use non-unicode character type locale
	local LC_CTYPE=C

	# Process Id of the previous running command
	local pid=$!

	local spin='⣾⣽⣻⢿⡿⣟⣯⣷'
	local char_width=3

	local i=0
	# cursor invisible
	tput civis
	while kill -0 "$pid" 2>/dev/null; do
		local i=$(((i + char_width) % ${#spin}))
		printf "%s" "${spin:$i:$char_width}"

		# Move cursor back
		echo -en "\033[1D"
		sleep .1
	done
	tput cnorm
	# Erase spinner and print new line. It is expected that the spinner
	# is shown at the end of message
	echo " "

	# Capture exit code
	wait "$pid"
	return $?
}

msg() {
	echo >&2 -e "$@"
}

parse_params() {
	# Default values of variables set from params
	flag=0
	param=''

	while :; do
		case "${1-}" in
		-h | --help) usage ;;
		--debug) set -x ;;
		--no-color) NO_COLOR=1 ;;

			# Example flag
		-f | --flag) flag=1 ;;

			# Example named parameter
		-p | --param)
			param="${2-}"
			shift
			;;
		-?*) die "Unknown option: $1" ;;
		*) break ;;
		esac
		shift
	done

	args=("$@")

	# Check required params and arguments
	[[ -z "${param-}" ]] && die "Missing required parameter: param"
	[[ ${#args[@]} -eq 0 ]] && die "Missing script arguments"

	return 0
}

parse_params "$@"
setup_colors

# Script logic here

msg "Read parameters:"
msg "- flag: ${flag}"
msg "- param: ${param}"
msg "- arguments: ${args[*]-}"

msg "${RED}Red${NOFORMAT}"
msg "${GREEN}Green${NOFORMAT}"
msg "${ORANGE}Orange${NOFORMAT}"
msg "${BLUE}Blue${NOFORMAT}"
msg "${PURPLE}Purple${NOFORMAT}"
msg "${CYAN}Cyan${NOFORMAT}"
msg "${YELLOW}Yellow${NOFORMAT}"
msg "${BOLD}Bold${NOFORMAT}"
msg "${BOLD}${RED}Bold red${NOFORMAT}"

msg "Script folder $script_dir"

msg -n "Sleeping 3 s with spinner "
sleep 3 &
spinner

msg "Done"
