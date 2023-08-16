#!/usr/bin/env bash

# Get the script location as it can be run from different place.
script_dir=$(dirname "$(realpath "$0")")

dotfiles_dir=$(dirname "$script_dir")
# shellcheck disable=SC1091
. "$dotfiles_dir/common.sh"

GITHUB_REPO="helix-editor/helix"
CONFIG_FOLDER="$HOME/.config/helix"

install_from_binary(){
	debug "Installing from precompiled binary"
	download_from_github "$GITHUB_REPO"
	package_path=$(find "$TMP_DIR" -name 'helix*')
	tar -xf "$package_path" -C "$TMP_DIR"

	package_name=$(basename "$package_path")
	debug "Downloaded package $package_name"

	helix_folder=$(find "$TMP_DIR" -name 'helix*' -type d)
	install_binary "$helix_folder/hx"
	debug "Installed into $BIN_FOLDER"
	
	debug "Copying helix runtimes"
	mkdir --parents "$CONFIG_FOLDER"
	rsync -a "$helix_folder/runtime" "$CONFIG_FOLDER/"
}

install_marksman() {
	MARKSMAN_GITHUB_REPO="artempyanykh/marksman"

	debug "Downloading from github repository $MARKSMAN_GITHUB_REPO"

	platform=$(uname -m)
	debug "Detected platform $platform"
	case "$platform" in
	  "x86_64")
	    platform="x64"
	    ;;
	  "aarch64")
	    platform="arm64"
	    ;;
	  *)
	    die "Platform is not supported"
	    ;;
	esac

	api="https://api.github.com/repos/$MARKSMAN_GITHUB_REPO/releases/latest"
	version=$(curl -s "$api" | grep -Po "\"tag_name\": \"\K[^\"]*")
	debug "Found latest version $version"

	# Download github api json for the specified repository
	package=$(curl -s "$api")
	# Filter out only package download links, each link on separate line
	package=$(echo "$package" | grep -Po "\"browser_download_url\":.*\"\K.*(?=\")" | tr " " "\n")
	# Filter only packages relevant for the platform
	package=$(echo "$package" | grep "$platform" | grep "linux")
	
	# If there is multiple packages remaining filter out gnu ve
	curl -LJOsSf "$package" --output-dir "$TMP_DIR"

	package_path=$(find "$TMP_DIR" -name 'marksman*')
	mv "$package_path" "$TMP_DIR/marksman"
	install_binary "$TMP_DIR/marksman"
	debug "Installed into $BIN_DIR"
}

install_additional_components() {
	debug "Installing additional components"

	debug "Installing Rust LSP (rust-analyzer)"
	rustup -q component add rust-analyzer >/dev/null 2>&1

	debug "Installing TOML LSP (taplo-cli)"
	cargo-binstall -y taplo-cli > /dev/null

	debug "Installing Bash LSP (bash-language-server)"
	# TODO install npm 16 first
	sudo npm install --silent -g bash-language-server >/dev/null 2>&1

	debug "Installing Markdown LSP (marksman)"
	install_marksman

	debug "Installing Python LSP"
	pip install python-lsp-server >/dev/null 2>&1

	debug "Installing Shfmt"
	curl -sS https://webi.sh/shfmt | sh >/dev/null 2>&1

}

link_configuration_files() {
	debug "Linking configuration files"
	# Create relative links to configuration files.
	CONFIG_LINKS="config.toml languages.toml themes"
	for link in $CONFIG_LINKS; do
		ln -sf "$script_dir/$link" "$CONFIG_FOLDER"
	done

}

info "Installation started"
apt_install "shellcheck"
install_from_binary
install_additional_components
link_configuration_files
debug "Installation done"
