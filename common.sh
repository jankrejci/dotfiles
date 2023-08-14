#!/usr/bin/env bash

set -eu

# Cleanup all temporary resources.
trap cleanup INT TERM EXIT

cleanup() {
	trap - INT TERM EXIT
	tput cnorm
}

die() {
	error "$1"
	exit 1
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

	date=$(date '+%Y-%m-%dT%H:%M:%S')
	printf '%s%s %s%-7s %s%-10s %s%s\n' \
		"${GREY}" "${date}" \
		"${color}" "${level}" \
		"${GREY}" "${MODULE_NAME}" \
		"${NO_COLOR}" "${text}" \
	>&2
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
Available options:

-h, --help      Print this help and exit
    --debug     Print script debug info
EOF
	exit
}

# shellcheck disable=SC2034
parse_params() {
	while :; do
		case "${1-}" in
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
apt_install() {
	packages="$*"
	for package in $packages; do
		if ! dpkg -s "$package" >/dev/null 2>&1; then
			debug "Installing \"$package\" through apt" 
			sudo apt -y install "$package" >/dev/null 2>&1
		fi
	done
}

github_release_link() {
	github_repo=$1
	if [ -z "$github_repo" ]; then
	    die "BUG: Github repo missing"
	fi

	platform=$(detect_platform)
	arch=$(detect_architecture)
	assets=$(curl -s "https://api.github.com/repos/$github_repo/releases/latest")

	download_url=$(echo "$assets" | \
		jq -r --arg platform "$platform" --arg arch "$arch" \
			'[.assets[].browser_download_url
			| select(
				contains($platform)
				and contains($arch)
				and contains("tar")
				# Filter out the checksum files
				and(contains(".sha256") | not)
			)]
			# Prefere musl versions
			| sort_by(contains("musl") | not)
			# If there is still more candidates, pick the first one
			| .[0]' \
	)

	if [ -n "$download_url" ]; then
	    filename=$(basename "$download_url")
		debug "Found release file \"$filename\""
	    echo "$download_url"
	else
	    die "BUG: Failed to find release file"
	fi
}

detect_platform() {
	platform=$(uname | tr '[:upper:]' '[:lower:]')
	if [ -z "$platform" ]; then
	    die "BUG: Failed to detect platform"
	else
		debug "Detected platform \"$platform\""
	fi
	
	echo "$platform"
}

detect_architecture() {
	arch=$(uname -m)
	if [ -z "$arch" ]; then
	    die "BUG: Failed to detect architecture"
	else
		debug "Detected architecture \"$arch\""
	fi
	
	echo "$arch"
}

download() {
	download_url=$1
	debug "Downloading file"
	curl -LJOsSf "$download_url" --output-dir "$TMP_DIR"	

    path=$TMP_DIR/$(basename "$download_url")
	if [ -f "$path" ]; then
		debug "Download was succesfull"
	else
		die "Failed to download the file"
	fi

	echo "$path"
}

download_from_github() {
	github_repo="$1"
	debug "Downloading from github repository $github_repo"

	link=$(github_release_link "$github_repo")
	path=$(download "$link")
	echo "$path"
}

install_binary() {
	binary_file="$1"

	BIN_FOLDER="/usr/local/bin/"
	chmod +x "$binary_file"
	mkdir --parents "$BIN_FOLDER"
	sudo mv "$binary_file" "$BIN_FOLDER"
}


parse_params "$@"
setup_colors

# Workaround to ask for sudo password at the beginning of the script,
# but not to run all commands as root
sudo echo -n

TMP_DIR="/tmp/dotfiles"
rm -rf "$TMP_DIR"
mkdir --parents "$TMP_DIR"

apt_install "curl" "jq"

BIN_DIR="/usr/local/bin"
CONFIG_DIR="$HOME/.config"

SCRIPT_DIR=$(dirname "$(realpath "$0")")
MODULE_NAME=$(basename "$SCRIPT_DIR")
info "Installing $MODULE_NAME"

