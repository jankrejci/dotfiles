# Description

Installs the development environment.

Each directory contains `install.sh` script. It installs the specific tool.
There is also install script in the root directory, which invokes these
specific install scripcts and thus installs all the tools at once.

## Installed tools
* [Rust](https://www.rust-lang.org/tools/install) A language empowering everyone to build reliable and efficient software.
* [Zellij](https://github.com/zellij-org/zellij) A terminal workspace with batteries included.
* [Helix](https://github.com/helix-editor/helix) Modal text editor.
* [Starship](https://github.com/starship/starship) Customizable prompt for any shell.
* [Alacritty](https://github.com/alacritty/alacritty) A fast, cross-platform, OpenGL terminal emulator.
* [Nushell](https://github.com/nushell/nushell) A new type of shell.

## Useful utils
* [Shellcheck](https://github.com/koalaman/shellcheck) A shell script static analysis tool
* [Shfmt](https://github.com/patrickvane/shfmt) A shell formater supporting Bash.
* [Lazygit](https://github.com/jesseduffield/lazygit) A simple terminal UI for Git commands.
* [Gitui](https://github.com/extrawurst/gitui) Blazing fast TUI for Git.


## Inatalled ependencies
* [Nerdfonts](https://github.com/ryanoasis/nerd-fonts) Iconic font aggregator, collection & patcher.
* Git
* Npm

# Instalation

You can run specific scripts individually to install required tool,
or run install script from root directory to install them all. 

```shell
chmod +x install.sh
./install.sh
```
