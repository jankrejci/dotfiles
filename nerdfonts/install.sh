#!/bin/bash

FONT_NAME="DejaVuSansMono"
FONT_FOLDER="$HOME/.local/share/fonts"

GITHUB_REPO="ryanoasis/nerd-fonts"
GITHUB_API="https://api.github.com/repos/$GITHUB_REPO/releases/latest"

VERSION=$(curl -s "$GITHUB_API" | grep -Po '"tag_name": "v\K[^"]*')

GITHUB_RELEASE="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/$FONT_NAME.zip"

echo "Nerd font installation"

echo "    • current version $VERSION"
echo "    • installing $FONT_NAME"
wget -q "$GITHUB_RELEASE" -P "/tmp"
unzip -o -q "/tmp/$FONT_NAME.zip" -d "$FONT_FOLDER"
rm "/tmp/$FONT_NAME.zip"

fc-cache -fv &>/dev/null
