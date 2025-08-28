#!/bin/bash

function is_rust_installed() {
	if command -v rustc &> /dev/null && command -v cargo &> /dev/null; then
		return 0 # Rust is installed
	else
		return 1 # Rust is not installed
	fi
}

# shellcheck disable=SC2120
function install_rust() {
	if [[ -z ${1+x} ]]; then
		user="$USER"
	else
		user="$1"
	fi
	local rustup_dir
	local rustup_url="https://sh.rustup.rs"
	local rustup_script="rustup-init.sh"
	rustup_dir="$(get_home_dir "$user")/.cargo"
	local rustup_bin="$rustup_dir/bin/rustup"

	if [ ! -f "$rustup_bin" ]; then
		logexec curl --proto '=https' --tlsv1.2 -sSf $rustup_url -o $rustup_script
		if [ "$user" != "$USER" ]; then
			chown "$user:$user" $rustup_script
			chmod +x $rustup_script
			logexec sudo -u "$user" ./$rustup_script -y
			sudo rm $rustup_script
		else
			chmod +x $rustup_script
			logexec ./$rustup_script -y
			rm $rustup_script
		fi
	fi
	install_apt_package build-essential

	if [ ! -d "$rustup_dir" ]; then
		echo "Rust installation failed."
		return 1
	fi

	export PATH="$PATH:$rustup_dir/bin"
	add_bashrc_lines '. "$HOME/.cargo/env"' "05_rust"
  source $HOME/.cargo/env
  rustup default stable
}

function install_rust_app() {
	appname=$1

	if [ -z "$appname" ]; then
		echo "No app name provided."
		return 1
	fi

	if ! command -v cargo &> /dev/null; then
		echo "Cargo is not installed. Please install Rust first."
		install_rust
	fi

	if cargo install --list | grep -q "^$appname "; then
		return 0 # Already installed
	fi

	logexec cargo install "$appname"
}
