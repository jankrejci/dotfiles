#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail

trap cleanup SIGINT SIGTERM ERR EXIT

cleanup() {
	trap - SIGINT SIGTERM ERR EXIT
	tput cnorm
	# rm -rf "$TMP_DIR"
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

Installs and configures Starship.

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
		sudo apt -y install "${not_installed_packages[@]}" &>/dev/null &
		spinner
	fi
}

sudo echo -n
setup_colors
parse_params "$@"


msg "${BOLD}Starship installation${NOFORMAT}"

TMP_DIR="/tmp/dotfiles"
mkdir --parent "$TMP_DIR"

msg -n "    • installing through install script"

SCRIPT_NAME="starship_install.sh"
curl -sS "https://starship.rs/install.sh" >"$TMP_DIR/$SCRIPT_NAME"
chmod +x "$TMP_DIR/$SCRIPT_NAME"
sudo "$TMP_DIR/$SCRIPT_NAME" -y &>/dev/null &
spinner

msg -n "    • adding init sequence to zshrc"
ZSHRC_FILE="$HOME/.zshrc"
if ! grep "starship" < "$ZSHRC_FILE" &>/dev/null; then
	echo 'eval "$(starship init zsh)' >>"$ZSHRC_FILE" 
fi

msg -n "    • linking configuration file"
ln -sf "$script_dir/startship.toml" "$HOME/.config/"
