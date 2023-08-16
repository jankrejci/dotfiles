#!/usr/bin/env bash
# shellcheck disable=SC2016

# Get the script location as it can be run from different place.
script_dir=$(dirname "$(realpath "$0")")

dotfiles_dir=$(dirname "$script_dir")
# shellcheck disable=SC1091
source "$dotfiles_dir/common.sh"

msg "${BOLD}Starship installation${NOFORMAT}"

TMP_DIR="/tmp/dotfiles"
mkdir --parent "$TMP_DIR"

msg -n "    • installing through install script"

SCRIPT_NAME="starship_install.sh"
curl -sS "https://starship.rs/install.sh" >"$TMP_DIR/$SCRIPT_NAME"
chmod +x "$TMP_DIR/$SCRIPT_NAME"
sudo "$TMP_DIR/$SCRIPT_NAME" -y &>/dev/null &
spinner

msg "    • adding init sequence to zshrc"
ZSHRC_FILE="$HOME/.zshrc"
if ! grep "starship" <"$ZSHRC_FILE" &>/dev/null; then
	echo 'eval "$(starship init zsh)"' >>"$ZSHRC_FILE"
fi

msg "    • linking configuration file"
ln -sf "$script_dir/startship.toml" "$HOME/.config/"
