#!/bin/bash

CONFIG_FOLDER="$HOME/.config/lazygit"
VERSION="0.37.0"
TARGET="x86_64"
SOURCE_FILE="lazygit_"$VERSION"_Linux_"$TARGET".tar.gz"
SOURCE_LINK="https://github.com/jesseduffield/lazygit/releases/download/v$VERSION/$SOURCE_FILE"
TMP_FOLDER="/tmp/lazygit"

echo "Lazygit installation"

echo "    • installing from precompiled binary system wide"
mkdir --parents "$TMP_FOLDER"
wget -q "$SOURCE_LINK" -P "$TMP_FOLDER"
tar -xf "$TMP_FOLDER/$SOURCE_FILE" -C "$TMP_FOLDER"
sudo install "$TMP_FOLDER/lazygit" /usr/local/bin

echo "    • linking configuration files"
mkdir --parents $CONFIG_FOLDER
ln -sf  $PWD/config.yml $CONFIG_FOLDER
