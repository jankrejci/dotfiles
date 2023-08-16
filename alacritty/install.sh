#!/usr/bin/env bash

# Get the script location as it can be run from different place.
script_dir=$(dirname "$(realpath "$0")")

dotfiles_dir=$(dirname "$script_dir")
# shellcheck disable=SC1091
source "$dotfiles_dir/common.sh"

build_from_source=false
config_folder="$HOME/.config/alacritty"

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
mkdir --parents "$config_folder"
ln -sf "$script_dir/alacritty.yml" "$config_folder"
sudo ln -sf "$script_dir/alacritty-simple.svg" "/usr/share/pixmaps/Alacritty.svg"
sudo ln -sf "$script_dir/Alacritty.desktop" "/usr/share/applications/"
sudo update-desktop-database
