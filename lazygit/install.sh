#!/bin/bash

CONFIG_FOLDER="$HOME/.config/lazygit"

TMP_FOLDER="/tmp/lazygit"

GITHUP_REPO="jesseduffield/lazygit"
GITHUB_API="https://api.github.com/repos/$GITHUP_REPO/releases/latest"
GITHUB_RELEASE="https://github.com/$GITHUB_REPO/releases/download/latest"

VERSION=$(curl -s "$GITHUB_API" | grep -Po '"tag_name": "v\K[^"]*')
TARGET="x86_64"
SOURCE_FILE="lazygit_"$VERSION"_Linux_"$TARGET".tar.gz"
SOURCE_LINK="$GITHUB_RELEASE/$SOURCE_FILE"

echo "Lazygit installation"

echo "    • installing version $VERSION from precompiled binary system wide"
mkdir --parents "$TMP_FOLDER"
wget -q "$SOURCE_LINK" -P "$TMP_FOLDER"
tar -xf "$TMP_FOLDER/$SOURCE_FILE" -C "$TMP_FOLDER"
sudo install "$TMP_FOLDER/lazygit" /usr/local/bin

echo "    • linking configuration files"
mkdir --parents $CONFIG_FOLDER
ln -sf  $PWD/config.yml $CONFIG_FOLDER
