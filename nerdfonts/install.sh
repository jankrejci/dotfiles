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
    FONT_NAME="DejaVuSansMono"
    FONT_FOLDER="$HOME/.local/share/fonts"

    GITHUB_REPO="ryanoasis/nerd-fonts"
    GITHUB_API="https://api.github.com/repos/$GITHUB_REPO/releases/latest"

    VERSION=$(curl -s "$GITHUB_API" | grep -Po '"tag_name": "v\K[^"]*')

    GITHUB_RELEASE="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/$FONT_NAME.zip"

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

msg "${BOLD}Nerd font installation${NOFORMAT}"

msg "    • current version $VERSION"
msg "    • installing $FONT_NAME"
wget -q "$GITHUB_RELEASE" -P "/tmp"
unzip -o -q "/tmp/$FONT_NAME.zip" -d "$FONT_FOLDER"
rm "/tmp/$FONT_NAME.zip"

fc-cache -fv &>/dev/null
