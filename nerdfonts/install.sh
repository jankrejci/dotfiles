#!/bin/bash

FONT_NAME="DejaVuSansMono"
FONT_LINK="https://github.com/ryanoasis/nerd-fonts/releases/download/v2.3.3/$FONT_NAME.zip"
FONT_FOLDER="$HOME/.local/share/fonts"

echo "Nerd font installation"

echo "    • installing $FONT_NAME"
wget "$FONT_LINK" -P "/tmp"
unzip -o -q "/tmp/$FONT_NAME.zip" -d "$FONT_FOLDER"
rm "/tmp/$FONT_NAME.zip"
 

fc-cache -fv