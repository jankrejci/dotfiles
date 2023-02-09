#!/bin/bash

CONFIG_FOLDER="$HOME/.config/git"

echo "Git installation"

echo "    • installing from Ubuntu package"
sudo apt -y install git &> /dev/null

echo "    • linking configuration files"
mkdir --parents $CONFIG_FOLDER
ln -sf  $PWD/config $CONFIG_FOLDER
