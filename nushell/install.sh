#!/usr/bin/env bash

# Get the script location as it can be run from different place.
script_dir=$(dirname "$(realpath "$0")")

dotfiles_dir=$(dirname "$script_dir")
# shellcheck disable=SC1091
source "$dotfiles_dir/common.sh"

build_from_source=false
cargo_bin="$HOME/.cargo/bin"
config_folder="$HOME/.config/nushell"
nushell_version="0.82.0"

link_configuration_files() {
	msg "    • linking configuration files"
	read -r -a configs <<<"$@"
	mkdir --parents "$config_folder"
	for config_file in "${configs[@]}"; do
		ln -sf "$script_dir/$config_file" "$config_folder"
	done
}

cargo_install () {
	msg -n "    • installing through cargo, it may take a while"
	cargo install nu --features=dataframe &>/dev/null &	spinner
}

install_from_binary(){
	BASE_ADDRESS="https://github.com/nushell/nushell/releases/download"
	package_name="nu-$nushell_version-$detected_platform-unknown-linux-gnu"
	package_file="$package_name.tar.gz"
	package_link="$BASE_ADDRESS/$nushell_version/$package_file"

	msg "    • installing version $nushell_version from binary"

	curl -LJsSf "$package_link" >"$TMP_DIR/$package_file"
	tar xf "$TMP_DIR/$package_file" --directory "$TMP_DIR"

	mv "$TMP_DIR/$package_name/nu" "$cargo_bin"
}

msg "${BOLD}NuShell installation${NOFORMAT}"

TMP_DIR="/tmp/dotfiles"
mkdir --parents "$TMP_DIR"

install_dependencies "pkg-config libssl-dev"

detected_platform=$(uname -m)
msg "    • detected platform $detected_platform"

if [ "$build_from_source" == true ]; then
	cargo_install
else
	install_from_binary
fi

link_configuration_files "env.nu config.nu"
