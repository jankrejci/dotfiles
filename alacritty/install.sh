#!/bin/bash

CONFIG_FOLDER="$HOME/.config/alacritty"

echo "Alacritty installation"
# Workaround to detect rpi platform
if [[ -f /usr/bin/rpi-update ]]; then
	echo "    • Raspberry Pi platform detected"
	echo "    • skipping install"
	exit
fi

echo "    • installing dependencies"
sudo apt -y install \
	cmake \
	pkg-config \
	libfreetype6-dev \
	libfontconfig1-dev \
	libxcb-xfixes0-dev \
	libxkbcommon-dev \
	python3 \
	&>/dev/null

echo "    • compiling from source, it may take a while"
cargo install --quiet alacritty

echo "    • linking configuration files"
mkdir --parents $CONFIG_FOLDER
ln -sf $PWD/alacritty.yml $CONFIG_FOLDER
sudo ln -sf $PWD/alacritty-simple.svg /usr/share/pixmaps/Alacritty.svg
sudo ln -sf $PWD/Alacritty.desktop /usr/share/applications/
sudo update-desktop-database
