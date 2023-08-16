#!/bin/bash

# Workaround to enter sudo password at the beginning of the script
sudo echo

echo "Installing dotfiles"
BASE_FOLDER=$(pwd)
CARGO_BIN="$HOME/.cargo/bin"

echo "    • installing Ubuntu packages"
sudo apt -y install npm &>/dev/null

echo "    • installing Rustup"
RUSTUP_INIT="/tmp/rustup-init.sh"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs >$RUSTUP_INIT
chmod +x $RUSTUP_INIT
$RUSTUP_INIT -y &>/dev/null
rm $RUSTUP_INIT
PATH=$PATH:$HOME/.cargo/bin/

DETECTED_PLATFORM=$(uname -m)
case ${DETECTED_PLATFORM} in
"x86_64")
	CARGO_BINSTALL="https://github.com/cargo-bins/cargo-binstall/releases/latest/download/cargo-binstall-x86_64-unknown-linux-musl.tgz"
	;;
"aarch64")
	CARGO_BINSTALL="https://github.com/cargo-bins/cargo-binstall/releases/latest/download/cargo-binstall-aarch64-unknown-linux-musl.tgz"
	;;
*)
	echo "    • unknown platform"
	exit
	;;
esac
echo "    • detected platform $DETECTED_PLATFORM"

echo "    • installing cargo-binstall from binary"
TMP_DIR="/tmp/cargo-binstall"
mkdir $TMP_DIR
cd $TMP_DIR
wget -q $CARGO_BINSTALL
tar zxf *
mv cargo-binstall $CARGO_BIN
cd $BASE_FOLDER
rm -rf $TMP_DIR

cd $BASE_FOLDER/git && ./install.sh
cd $BASE_FOLDER/nerdfonts && ./install.sh
cd $BASE_FOLDER/alacritty && ./install.sh
cd $BASE_FOLDER/zellij && ./install.sh
cd $BASE_FOLDER/helix && ./install.sh
cd $BASE_FOLDER/lazygit && ./install.sh
