#!/bin/bash

# This is the default path, where the configuration is stored
CONFIG_FOLDER="$HOME/.config/helix"
INSTALL_FOLDER=`pwd`


# Helix instalation from the source, more info in documentation
# https://docs.helix-editor.com/install.html
echo "Cloning Helix repository"
cd /tmp
rm -rf helix
git clone --quiet https://github.com/helix-editor/helix

echo "Installing Helix editor"
cd helix
cargo install --quiet --locked --path helix-term

echo "Copying Helix runtimes"
# Copy runtime files
rsync -a runtime $CONFIG_FOLDER/

# Install language servers
echo "Installing language servers"

# Rust
echo "  • Rust (rust-analyzer)"
rustup -q component add rust-analyzer

# TOML
echo "  • TOML (taplo-cli)"
cargo install --quiet taplo-cli --locked --features lsp

# Bash
echo "  • Bash (bash-language-server)"
npm install --silent -g bash-language-server

# Marksdown
MARKSMAN_BINARY="https://github.com/artempyanykh/marksman/releases/download/2022-12-28/marksman-linux"
BIN_FOLDER="$HOME/.local/bin"
BINARY_NAME="marksman"
wget -q $MARKSMAN_BINARY
mv marksman-linux $BINARY_NAME
chmod +x $BINARY_NAME
mv $BINARY_NAME $BIN_FOLDER

cd $INSTALL_FOLDER
# Create configuration directory , it creates also the parent
# directory if it is not exists already. If the configuration
# directory already exist it changes nothing.
echo "Linking configuration files"
mkdir --parents $CONFIG_FOLDER

# Create relative links to configuration files. If the file
# exists already, it wil overwrites it.
ln -srf config.toml $CONFIG_FOLDER
ln -srf languages.toml $CONFIG_FOLDER
ln -srf themes $CONFIG_FOLDER
