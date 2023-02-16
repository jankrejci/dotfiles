#!/usr/bin/env bash

set -Eeuo pipefail

trap cleanup SIGINT SIGTERM ERR EXIT

cleanup() {
	trap - SIGINT SIGTERM ERR EXIT
	tput cnorm
	# Script cleanup here
	rm -rf "$TMP_DIR"
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

die() {
	local msg=$1
	local code=${2-1}
	msg "${RED}$msg${NOFORMAT}"
	exit "$code"
}

setup_colors() {
	if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
		NOFORMAT='\033[0m'
		RED='\033[0;31m'
		BOLD='\033[1m'
	else
		NOFORMAT='' RED='' BOLD=''
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
Usage: $(basename "${BASH_SOURCE[0]}") [-s]

Installs and configures Helix editor.

Available options:

-s, --source    Build Helix from source
-h, --help      Print this help and exit
    --debug     Print script debug info
    --no-color  Print without colors
EOF
	exit
}

parse_params() {
	build_from_source=false
	config_folder="$HOME/.config/helix"
	cargo_bin="$HOME/.cargo/bin"
	helix_version="22.12"

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
	# Helix instalation from the source, more info in documentation
	# https://docs.helix-editor.com/install.html
	msg -n "    • cloning Helix repository"
	REPO_LINK="https://github.com/helix-editor/helix"
	git clone --quiet "$REPO_LINK" "$TMP_DIR/helix" &
	spinner
	
	msg -n "    • installing from source, it may take a while"
	cd "$TMP_DIR/helix"
	cargo install --quiet --locked --path helix-term &>/dev/null &
	spinner
}

install_marksman() {
	BASE_ADDRESS="https://github.com/artempyanykh/marksman/releases/download/2022-12-28"
	PACKAGE_FILE="marksman-linux"
	package_link="$BASE_ADDRESS/$PACKAGE_FILE"

	BIN_FOLDER="$HOME/.local/bin"
	BINARY_NAME="marksman"

	curl --proto "=https" --tlsv1.2 -LJsSf "$package_link" >"$TMP_DIR/$BINARY_NAME"
	chmod +x "$TMP_DIR/$BINARY_NAME"
	mv "$TMP_DIR/$BINARY_NAME" "$BIN_FOLDER"
}

msg "${BOLD}Helix installation${NOFORMAT}"

TMP_DIR="/tmp/dotfiles"
mkdir --parents "$TMP_DIR"

install_dependencies "npm"

detected_platform=$(uname -m)
msg "    • detected platform $detected_platform"

if [ "$build_from_source" == true ]; then
	install_from_source
else
	msg -n "    • installing version $helix_version from binary"
	install_from_binary &
	spinner
fi


# Copy runtime files
echo "    • copying runtimes"
runtime_folder="$TMP_DIR/helix-$helix_version-$detected_platform-linux/runtime"
if [ "$build_from_source" == true ]; then
	runtime_folder="$TMP_DIR/helix/runtime"
fi
rsync -a "$runtime_folder" "$config_folder/"

# Install language servers
echo "    • Installing language servers"
cd "$script_dir"

# Rust
echo -n "        • Rust (rust-analyzer)"
rustup -q component add rust-analyzer &>/dev/null &
spinner

# TOML
echo -n "        • TOML (taplo-cli)"
if [ "$build_from_source" == true ]; then
	cargo install --quiet taplo-cli --locked --features lsp &
	spinner
else
	cargo-binstall -y taplo-cli &>/dev/null &
	spinner
fi

# Bash
echo -n "        • Bash (bash-language-server)"
npm install --silent -g bash-language-server &>/dev/null &
spinner

# Markdown
echo -n "        • Markdown (marksman)"
install_marksman &
spinner

echo "    • linking configuration files"
mkdir --parents "$config_folder"
# Create relative links to configuration files.
CONFIG_LINKS=("config.toml" "languages.toml" "themes")
for link in "${CONFIG_LINKS[@]}"; do
	ln -sf "$script_dir/$link" "$config_folder"
done
