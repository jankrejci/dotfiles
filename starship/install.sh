#!/usr/bin/env sh
# shellcheck disable=SC2016

# Get the script location as it can be run from different place.
script_dir=$(dirname "$(realpath "$0")")

dotfiles_dir=$(dirname "$script_dir")
. "$dotfiles_dir/common.sh"

info "Installation started"

debug "Installing through install script"

SCRIPT_NAME="starship_install.sh"
curl -sS "https://starship.rs/install.sh" >"$TMP_DIR/$SCRIPT_NAME"
chmod +x "$TMP_DIR/$SCRIPT_NAME"
sudo "$TMP_DIR/$SCRIPT_NAME" -y >/dev/null 2>&1

debug "Adding init sequence to zshrc"
ZSHRC_FILE="$HOME/.zshrc"
if ! grep "starship" <"$ZSHRC_FILE" >/dev/null 2>&1; then
	echo 'eval "$(starship init zsh)"' >>"$ZSHRC_FILE"
fi

debug "Linking configuration file"
ln -sf "$script_dir/startship.toml" "$HOME/.config/"

debug "Installation done"
