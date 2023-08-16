#!/usr/bin/env sh

set -eu

# Cleanup all temporary resources.
trap cleanup INT TERM EXIT

cleanup() {
	trap - INT TERM EXIT
	tput cnorm
	# Script cleanup here
}

die() {
	# Default exit status 1
	code="${2-1}"
	error "$*"
	exit "$code"
}

# shellcheck disable=SC2034
setup_colors() {
	GREY="$(tput setaf 245 2>/dev/null || printf '')"
	RED="$(tput setaf 1 2>/dev/null || printf '')"
	GREEN="$(tput setaf 2 2>/dev/null || printf '')"
	YELLOW="$(tput setaf 3 2>/dev/null || printf '')"
	CYAN="$(tput setaf 6 2>/dev/null || printf '')"
	NO_COLOR="$(tput sgr0 2>/dev/null || printf '')"
}

message() {
	color=$1
	level=$2
	text=$3

	dir_name=$(dirname "$(realpath "$0")")
	module=$(basename "$dir_name")
	date=$(date '+%Y-%m-%dT%H:%M:%S')
	printf '%s%s %s%-7s %s%-10s %s%s\n' \
		"${GREY}" "${date}" \
		"${color}" "${level}" \
		"${GREY}" "${module}" \
		"${NO_COLOR}" "${text}"
}

info() {
	message "${GREEN}" "[INFO]" "$*"
}

debug() {
	message "${CYAN}" "[DEBUG]" "$*"
}

warn() {
	message "${YELLOW}" "[WARN]" "$*"
}

error() {
	message "${RED}" "[ERROR]" "$*"
}

usage() {
	cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}")

Available options:

-l, --local     Install binaries into user's home
-h, --help      Print this help and exit
    --debug     Print script debug info
EOF
	exit
}

# shellcheck disable=SC2034
parse_params() {
	LOCAL_INSTALL=false
	
	while :; do
		case "${1-}" in
		-l | --local) LOCAL_INSTALL=true ;;
		-h | --help) usage ;;
		--debug) set -x ;;
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
	packages="$1"
	for package in $packages; do
		if ! dpkg -s "$package" >/dev/null 2>&1; then
			debug "Installing packages through apt" "$package"
			sudo apt -y install "$package" >/dev/null 2>&1
		fi
	done
}

download_from_github() {
	repository="$1"
	debug "Downloading precompiled package from github repository $repository"

	platform=$(uname -m)
	debug "Detected platform $platform"

	api="https://api.github.com/repos/$repository/releases/latest"
	version=$(curl -s "$api" | grep -Po "\"tag_name\": \"\K[^\"]*")
	debug "Found latest version $version"

	# Download github api json for the specified repository
	package=$(curl -s "$api")
	# Filter out only package download links, each link on separate line
	package=$(echo "$package" | grep -Po "\"browser_download_url\":.*\"\K.*(?=\")" | tr " " "\n")
	# Filter only packages relevant for the platform
	package=$(echo "$package" | grep "$platform" | grep "linux" | grep "tar")
	
	# If there is multiple packages remaining filter out gnu version
	if [ "$(echo "$package" | grep -c .)" -gt 1 ]; then
		package=$(echo "$package" | grep "gnu")
	fi

	curl -LJOsSf "$package" --output-dir "$TMP_DIR"
}

install_binary() {
	binary_file="$1"

	if [ "$LOCAL_INSTALL" = true ]; then
		BIN_FOLDER="/usr/local/bin/"
		chmod +x "$binary_file"
		mkdir --parents "$BIN_FOLDER"
		sudo mv "$binary_file" "$BIN_FOLDER"
	else
		BIN_FOLDER="/usr/local/bin/"
		sudo chown "root:root" "$binary_file"
		sudo chmod 755 "$binary_file"
		sudo mv "$binary_file" "$BIN_FOLDER"
	fi
}


parse_params "$@"
setup_colors

# Workaround to ask for sudo password at the beginning of the script,
# but not to run all commands as root
if [ "$LOCAL_INSTALL" = false ]; then
	sudo echo -n
fi

TMP_DIR="/tmp/dotfiles"
rm -rf "$TMP_DIR"
mkdir --parents "$TMP_DIR"
