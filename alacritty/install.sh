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
		echo -en "\033[1D"
		sleep .1
	done
	tput cnorm;	msg " ";
	wait "$pid"
	return $?
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
	build_from_source=false
	config_folder="$HOME/.config/alacritty"

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

install_from_binary(){
	BASE_ADDRESS="https://github.com/helix-editor/helix/releases/download"
	package_name="helix-$helix_version-$detected_platform-linux"
	package_file="$package_name.tar.xz"
	package_link="$BASE_ADDRESS/$helix_version/$package_file"

	curl -LJsSf "$package_link" >"$TMP_DIR/$package_file"
	tar xf "$TMP_DIR/$package_file" --directory "$TMP_DIR"

	mv "$TMP_DIR/$package_name/hx" "$cargo_bin"
}

install_from_source(){
	msg -n "    • installing through cargo, it may take a while"
	cargo install --quiet alacritty &>/dev/null & spinner
}

msg "${BOLD}Alacritty installation${NOFORMAT}"

# Workaround to detect rpi platform
if [[ -f /usr/bin/rpi-update ]]; then
	msg "    • Raspberry Pi platform detected"
	msg "    • skipping install"
	exit
fi

install_dependencies \
	"cmake \
	pkg-config \
    libfreetype6-dev \
	libfontconfig1-dev \
	libxcb-xfixes0-dev \
	libxkbcommon-dev \
	python3"

if [ "$build_from_source" == true ]; then
	install_from_source
fi

msg "    • linking configuration files"
mkdir --parents $config_folder
ln -sf $PWD/alacritty.yml $config_folder
sudo ln -sf $PWD/alacritty-simple.svg /usr/share/pixmaps/Alacritty.svg
sudo ln -sf $PWD/Alacritty.desktop /usr/share/applications/
sudo update-desktop-database
