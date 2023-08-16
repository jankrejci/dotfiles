#!/bin/bash

CONFIG_FOLDER="$HOME/.config/zellij"

echo "Zellij installation"

echo "    • installing dependencies for Ubuntu"
sudo apt -y install \
fonts-powerline \
&> /dev/null

# echo "    • compiling from source, it may take a while"
# cargo install --quiet --locked zellij

echo "    • installing from precompiled binary"
cargo binstall -y zellij &> /dev/null

echo "    • linking configuration files"
mkdir --parents $CONFIG_FOLDER
ln -sf  $PWD/config.kdl $CONFIG_FOLDER
rm -rf "$CONFIG_FOLDER/themes"
ln -sf  $PWD/themes $CONFIG_FOLDER
rm -rf "$CONFIG_FOLDER/layouts"
ln -sf  $PWD/layouts $CONFIG_FOLDER
