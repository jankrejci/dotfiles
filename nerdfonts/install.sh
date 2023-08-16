#!/usr/bin/env sh

# Get the script location as it can be run from different place.
script_dir=$(dirname "$(realpath "$0")")

dotfiles_dir=$(dirname "$script_dir")
# shellcheck disable=SC1091
. "$dotfiles_dir/common.sh"

FONT_NAME="DejaVuSansMono"

FONT_FOLDER="/usr/share/fonts/$FONT_NAME"
if [ "$LOCAL_INSTALL" = true ]; then
    FONT_FOLDER="$HOME/.local/share/fonts/$FONT_NAME"
fi
sudo mkdir --parents "$FONT_FOLDER"

GITHUB_REPO="ryanoasis/nerd-fonts"
GITHUB_API="https://api.github.com/repos/$GITHUB_REPO/releases/latest"
VERSION=$(curl -s "$GITHUB_API" | grep -Po '"tag_name": "v\K[^"]*')
GITHUB_RELEASE="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/$FONT_NAME.zip"

info "Installation started"
apt_install "fontconfig"

debug "Current version $VERSION"
debug "Installing $FONT_NAME"
wget -q "$GITHUB_RELEASE" -P "/tmp"
sudo unzip -o -q "/tmp/$FONT_NAME.zip" -d "$FONT_FOLDER"

fc-cache -fv >/dev/null 2>&1
debug "Installation done"

