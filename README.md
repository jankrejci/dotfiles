# Description

Working environment defined with Nix and home-manager

# Installation

Install nix prefarably through the [nix-installer](https://github.com/DeterminateSystems/nix-installer)
```shell
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```
Install home manager and create flake.nix and home.nix under ~/.config/home-manager
```shell
nix run home-manager/master -- init --switch
```
Clone configuration to home-manager folder
```shell
git clone https://github.com/jankrejci/dotfiles.git ~/.config/home-manager
```
Switch to the new configuration
```shell
home-manager switch
```

# Update packages
Update package versions in flake.lock
```shell
cd ~/.config/home-manager; nix flake update
```
Install updated packages
```shell
home-manager switch
```
Remove old generations
```shell
 home-manager expire-generations "-30 days"
```
Cleanup unused packages from nix store
```shell
nix-store --gc
```

# Packages

## Core tools
* [Rust](https://www.rust-lang.org/tools/install) A language empowering everyone to build reliable and efficient software.
* [Zellij](https://github.com/zellij-org/zellij) A terminal workspace with batteries included.
* [Helix](https://github.com/helix-editor/helix) Modal text editor.
* [Starship](https://github.com/starship/starship) Customizable prompt for any shell.
* [Alacritty](https://github.com/alacritty/alacritty) A fast, cross-platform, OpenGL terminal emulator.
* [Nushell](https://github.com/nushell/nushell) A new type of shell.

## Useful utils
* [Shellcheck](https://github.com/koalaman/shellcheck) A shell script static analysis tool
* [Shfmt](https://github.com/patrickvane/shfmt) A shell formater supporting Bash.
* [Gitui](https://github.com/extrawurst/gitui) Blazing fast TUI for Git.
* [Nerdfonts](https://github.com/ryanoasis/nerd-fonts) Iconic font aggregator, collection & patcher.
