#!/bin/bash

# Workaround to enter sudo password at the beginning of the script
sudo echo

echo "Installing dotfiles"
BASE_FOLDER=`pwd`


echo "    • installing Rustup"
RUSTUP_INIT="/tmp/rustup-init.sh"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs > $RUSTUP_INIT
chmod +x $RUSTUP_INIT
$RUSTUP_INIT -y &> /dev/null
rm $RUSTUP_INIT

echo "    • installing Ubuntu packages"
sudo apt -y install \
git \
npm \
&> /dev/null

cd $BASE_FOLDER/alacritty && ./install.sh
cd $BASE_FOLDER/zellij && ./install.sh
cd $BASE_FOLDER/helix && ./install.sh
