#!/bin/bash

CONFIG_FOLDER="$HOME/.config/zellij"
BUILD_FROM_SOURCE=false

print_help() {
	echo "Nothing to be seen here"
}

process_args() {
	VALID_ARGS=$(getopt -o sh --long source,help -- "$@")
	if [[ $? -ne 0 ]]; then
		exit 1
	fi
	eval set -- "$VALID_ARGS"
	while [ : ]; do
		case "$1" in
		-s | --source)
			BUILD_FROM_SOURCE=true
			shift
			;;
		-h | --help)
			print_help
			shift
			;;
		--)
			shift
			break
			;;
		esac
	done
}

install_dependencies() {
	echo "    • installing Ubuntu dependencies"
	sudo apt -y install fonts-powerline &>/dev/null
}

install_from_binary() {
	echo "    • installing from precompiled binary"
	cargo binstall -y zellij &>/dev/null
}

install_from_source() {
	echo "    • compiling from source, it may take a while"
	cargo install --quiet --locked zellij
}

process_args "$@"

echo "Zellij installation"

install_dependencies

if [ $BUILD_FROM_SOURCE == true ]; then
	install_from_source
else
	install_from_binary
fi

echo "    • linking configuration files"
mkdir --parents "$CONFIG_FOLDER"
ln -sf "$PWD/config.kdl" "$CONFIG_FOLDER"
rm -rf "$CONFIG_FOLDER/themes"
ln -sf "$PWD/themes" "$CONFIG_FOLDER"
rm -rf "$CONFIG_FOLDER/layouts"
ln -sf "$PWD/layouts" "$CONFIG_FOLDER"
