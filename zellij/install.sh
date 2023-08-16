#!/bin/bash

CONFIG_FOLDER="$HOME/.config/zellij"

echo "Installing Zellij from source, it may take a while"
cargo install --quiet --locked zellij


echo "Installing Zellij requirements"
sudo apt install fonts-powerline

echo "Linking configuration files"
mkdir --parents $CONFIG_FOLDER
ln -srf  config.kdl $CONFIG_FOLDER
rm -rf "$CONFIG_FOLDER/themes"
ln -srf  themes $CONFIG_FOLDER
rm -rf "$CONFIG_FOLDER/layouts"
ln -srf  layouts $CONFIG_FOLDER
