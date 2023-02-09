#!/bin/bash

CONFIG_FOLDER="$HOME/.config/lazygit"

TARGET="x86_64"
TMP_FOLDER="/tmp/lazygit"

GITHUB_REPO="jesseduffield/lazygit"
GITHUB_API="https://api.github.com/repos/$GITHUB_REPO/releases/latest"

echo "Lazygit installation"

# Detect the latest version
VERSION=$(curl -s "$GITHUB_API" | grep -Po '"tag_name": "v\K[^"]*')
if [ -n "${VERSION}" ]; then
  echo "    • version $VERSION"
else
  # Red text color
  echo -en "\033[0;31m"
  echo "    • failed to detect latest version"
  echo -en "\033[0m"
  exit 1
fi

GITHUB_RELEASE="https://github.com/$GITHUB_REPO/releases/download/v$VERSION"
SOURCE_FILE="lazygit_"$VERSION"_Linux_"$TARGET".tar.gz"
SOURCE_LINK="$GITHUB_RELEASE/$SOURCE_FILE"

echo "    • installing from precompiled binary system wide"
mkdir --parents "$TMP_FOLDER"
wget -q "$SOURCE_LINK" -P "$TMP_FOLDER"
tar -xf "$TMP_FOLDER/$SOURCE_FILE" -C "$TMP_FOLDER"
sudo install "$TMP_FOLDER/lazygit" /usr/local/bin

echo "    • linking configuration files"
mkdir --parents $CONFIG_FOLDER
ln -sf  $PWD/config.yml $CONFIG_FOLDER
