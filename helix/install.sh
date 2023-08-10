#!/usr/bin/env bash

# Get the script location as it can be run from different place.
script_dir=$(dirname "$(realpath "$0")")

dotfiles_dir=$(dirname "$script_dir")
# shellcheck disable=SC1091
source "$dotfiles_dir/common.sh"

GITHUB_REPO="helix-editor/helix"
CONFIG_FOLDER="$HOME/.config/helix"

install_from_binary(){
	msg "    • installing from precompiled binary"
	download_from_github "$GITHUB_REPO"
	package_path=$(find "$TMP_DIR" -name 'helix*')
	tar -xf "$package_path" -C "$TMP_DIR"

	package_name=$(basename "$package_path")
	msg "    • downloaded package $package_name"

	helix_folder=$(find "$TMP_DIR" -name 'helix*' -type d)
	install_binary "$helix_folder/hx"
	msg "    • installed into $BIN_FOLDER"
	
	echo "    • copying helix runtimes"
	mkdir --parents "$CONFIG_FOLDER"
	rsync -a "$helix_folder/runtime" "$CONFIG_FOLDER/"
}

install_marksman() {
	MARKSMAN_GITHUB_REPO="artempyanykh/marksman"

	msg "            • downloading from github repository $MARKSMAN_GITHUB_REPO"

	platform=$(uname -m)
	msg "            • detected platform $platform"
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
	msg "            • found latest version $version"

	# Download github api json for the specified repository
	package=$(curl -s "$api")
	# Filter out only package download links, each link on separate line
	package=$(grep -Po "\"browser_download_url\":.*\"\K.*(?=\")" <<<"$package" | tr " " "\n")
	# Filter only packages relevant for the platform
	package=$(echo "$package" | grep "$platform" | grep "linux")
	
	# If there is multiple packages remaining filter out gnu ve
	curl -LJOsSf "$package" --output-dir "$TMP_DIR"

	package_path=$(find "$TMP_DIR" -name 'marksman*')
	mv "$package_path" "$TMP_DIR/marksman"
	install_binary "$TMP_DIR/marksman"
	msg "            • installed into $BIN_FOLDER"
}

install_additional_components() {
	msg "    • installing additional components"

	msg -n "        • Rust LSP (rust-analyzer)"
	rustup -q component add rust-analyzer &>/dev/null & spinner

	msg -n "        • TOML LSP (taplo-cli)"
	cargo-binstall -y taplo-cli > /dev/null & spinner

	msg -n "        • Bash LSP (bash-language-server)"
	sudo npm install --silent -g bash-language-server &>/dev/null & spinner

	msg "        • Markdown LSP (marksman)"
	install_marksman

	msg -n "        • Python LSP"
	pip install python-lsp-server &>/dev/null & spinner

	msg -n "        • Shfmt"
	curl -sS https://webi.sh/shfmt | sh &>/dev/null & spinner

}

link_configuration_files() {
	echo "    • linking configuration files"
	# Create relative links to configuration files.
	CONFIG_LINKS=("config.toml" "languages.toml" "themes")
	for link in "${CONFIG_LINKS[@]}"; do
		ln -sf "$script_dir/$link" "$CONFIG_FOLDER"
	done

}

msg "${BOLD}Helix installation${NOFORMAT}"
apt_install "npm shellcheck"
install_from_binary
install_additional_components
link_configuration_files
msg "${GREEN}    • instalation done${NOFORMAT}"
