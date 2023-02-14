#!/bin/bash

HELIX_VERSION="22.12"
INSTALL_FROM_SOURCE=false

echo "Helix installation"

# This is the default path, where the configuration is stored
CONFIG_FOLDER="$HOME/.config/helix"
INSTALL_FOLDER=$(pwd)

if [ -z "$CARGO_BIN" ]; then
	CARGO_BIN="$HOME/.cargo/bin"
fi

if [ -z "$DETECTED_PLATFORM" ]; then
	DETECTED_PLATFORM=$(uname -m)
fi
echo "    • detected platform $DETECTED_PLATFORM"

# Remove temporary installation foder if it exists
TMP_FOLDER="/tmp/helix"
rm -rf $TMP_FOLDER

if [ "$INSTALL_FROM_SOURCE" = true ]; then
	# Helix instalation from the source, more info in documentation
	# https://docs.helix-editor.com/install.html
	echo "    • cloning repository to $TMP_FOLDER"
	git clone --quiet https://github.com/helix-editor/helix $TMP_FOLDER

	echo "    • installing from source, it may take a while"
	cd $TMP_FOLDER
	cargo install --quiet --locked --path helix-term
else
	echo "    • installing version $HELIX_VERSION from binary"
	HELIX_BINARY="https://github.com/helix-editor/helix/releases/download/$HELIX_VERSION/helix-$HELIX_VERSION-$DETECTED_PLATFORM-linux.tar.xz"
	mkdir $TMP_FOLDER
	cd $TMP_FOLDER
	wget -q $HELIX_BINARY
	tar xf *.tar.xz
	rm *.tar.xz
	cd "helix-$HELIX_VERSION-$DETECTED_PLATFORM-linux"
	mv "hx" "$CARGO_BIN"
fi

echo "    • copying runtimes"
# Copy runtime files
rsync -a runtime $CONFIG_FOLDER/
cd ..
rm -rf helix

# Install language servers
echo "    • Installing language servers"

# Rust
echo "        • Rust (rust-analyzer)"
rustup -q component add rust-analyzer &>/dev/null

# TOML
echo "        • TOML (taplo-cli)"
if [ "$INSTALL_FROM_SOURCE" = true ]; then
	cargo install --quiet taplo-cli --locked --features lsp
else
	cargo-binstall -y taplo-cli &>/dev/null
fi

# Bash
echo "        • Bash (bash-language-server)"
npm install --silent -g bash-language-server

# Markdown
echo "        • Markdown (marksman)"
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
echo "    • linking configuration files"
mkdir --parents $CONFIG_FOLDER

# Create relative links to configuration files. If the file
# exists already, it wil overwrites it.
ln -sf $PWD/config.toml $CONFIG_FOLDER
ln -sf $PWD/languages.toml $CONFIG_FOLDER
ln -sf $PWD/themes $CONFIG_FOLDER
