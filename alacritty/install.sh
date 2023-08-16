#!/bin/bash

echo "Alacritty installation"
echo "    • installing dependencies"
sudo apt -y install \
cmake \
pkg-config \
libfreetype6-dev \
libfontconfig1-dev \
libxcb-xfixes0-dev \
libxkbcommon-dev \
python3 \
&> /dev/null

echo "    • compiling from source, it may take a while"
cargo install --quiet alacritty

echo "    • linking configuration files"
sudo ln -srf alacritty-simple.svg /usr/share/pixmaps/Alacritty.svg
sudo ln -srf Alacritty.desktop /usr/share/applications/
sudo update-desktop-database
