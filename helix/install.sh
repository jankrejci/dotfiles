#!/usr/bin/env bash

# Get the script location as it can be run from different place.
script_dir=$(dirname "$(realpath "$0")")

dotfiles_dir=$(dirname "$script_dir")
# shellcheck disable=SC1091
source "$dotfiles_dir/common.sh"

build_from_source=false
github_repo="helix-editor/helix"
config_folder="$HOME/.config/helix"
cargo_bin="$HOME/.cargo/bin"
helix_version="23.05"

install_from_binary(){
	msg "    • installing from precompiled binary"
	download_from_github "$github_repo" "$TMP_DIR"
	package_path=$(find "$TMP_DIR" -name 'helix*')
	tar -xf "$package_path" -C "$TMP_DIR"
	helix_folder=$(find "$TMP_DIR" -name 'helix*' -type d)
	mv "$helix_folder/hx" "$cargo_bin"
}

install_from_source(){
	# Helix instalation from the source, more info in documentation
	# https://docs.helix-editor.com/install.html
	msg -n "    • cloning Helix repository"
	REPO_LINK="https://github.com/helix-editor/helix"
	git clone --quiet "$REPO_LINK" "$TMP_DIR/helix" & spinner
	
	msg -n "    • installing from source, it may take a while"
	cd "$TMP_DIR/helix" || exit
	cargo install --quiet --locked --path helix-term &>/dev/null & spinner
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
rm -rf "$TMP_DIR"
mkdir --parents "$TMP_DIR"

apt_install "npm shellcheck"


detected_platform=$(uname -m)
msg "    • detected platform $detected_platform"

if [ "$build_from_source" == true ]; then
	install_from_source
else
	install_from_binary
fi


# Copy runtime files
echo "    • copying runtimes"
runtime_folder="$TMP_DIR/helix-$helix_version-$detected_platform-linux/runtime"
if [ "$build_from_source" == true ]; then
	runtime_folder="$TMP_DIR/helix/runtime"
fi
rsync -a "$runtime_folder" "$config_folder/"

msg -n "    • installing shfmt"
curl -sS https://webi.sh/shfmt | sh &>/dev/null & spinner

# Install language servers
echo "    • installing language servers"
cd "$script_dir" || exit

# Rust
echo -n "        • Rust (rust-analyzer)"
rustup -q component add rust-analyzer &>/dev/null & spinner

# TOML
echo -n "        • TOML (taplo-cli)"
if [ "$build_from_source" == true ]; then
	cargo install --quiet taplo-cli --locked --features lsp & spinner
else
	cargo-binstall -y taplo-cli &>/dev/null & spinner
fi

# Bash
# echo -n "        • Bash (bash-language-server)"
# npm install --silent -g bash-language-server &>/dev/null & spinner

# Markdown
echo -n "        • Markdown (marksman)"
install_marksman & spinner

echo "    • linking configuration files"
mkdir --parents "$config_folder"
# Create relative links to configuration files.
CONFIG_LINKS=("config.toml" "languages.toml" "themes")
for link in "${CONFIG_LINKS[@]}"; do
	ln -sf "$script_dir/$link" "$config_folder"
done
