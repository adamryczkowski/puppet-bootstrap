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
  # Determine target user robustly:
  # 1) explicit param
  # 2) 'user' variable from calling script (prepare_ubuntu_user.sh)
  # 3) SUDO_USER when present and non-root
  # 4) fallback to current USER
  local target_user
  if [[ -n ${1+x} && -n "$1" ]]; then
    target_user="$1"
  elif [[ -n ${user+x} && -n "$user" ]]; then
    target_user="$user"
  elif [[ -n ${SUDO_USER+x} && "$SUDO_USER" != "" && "$SUDO_USER" != "root" ]]; then
    target_user="$SUDO_USER"
  else
    target_user="$USER"
  fi

  local rustup_url="https://sh.rustup.rs"
  # Download to /tmp to ensure accessibility for all users
  local rustup_script="/tmp/rustup-init-$$.sh"
  local target_home
  target_home="$(get_home_dir "$target_user")"
  local rustup_dir="${target_home}/.cargo"
  local rustup_bin="${rustup_dir}/bin/rustup"

  if [ ! -f "$rustup_bin" ]; then
    logexec curl --proto '=https' --tlsv1.2 -sSf "$rustup_url" -o "$rustup_script"
    chmod +x "$rustup_script"
    if [ "$target_user" != "$USER" ]; then
      chown "$target_user:$target_user" "$rustup_script"
      # Ensure HOME points to target user's home so rustup installs there
      logexec sudo -H -u "$target_user" env HOME="$target_home" RUSTUP_INIT_SKIP_PATH_CHECK=yes "$rustup_script" -y
      rm -f "$rustup_script"
    else
      # Override HOME in case sudo -E preserved the caller HOME
      logexec env HOME="$target_home" RUSTUP_INIT_SKIP_PATH_CHECK=yes "$rustup_script" -y
      rm -f "$rustup_script"
    fi
  fi

  install_apt_package build-essential

  if [ ! -d "$rustup_dir" ]; then
    echo "Rust installation failed."
    return 1
  fi

  export HOME="$target_home"
  export PATH="$PATH:$rustup_dir/bin"
  add_bashrc_lines '. "$HOME/.cargo/env"' "05_rust" "$target_user"
  if [ -f "$target_home/.cargo/env" ]; then
    # shellcheck disable=SC1090
    . "$target_home/.cargo/env"
  fi
  logexec sudo -H -u "$target_user" env HOME="$target_home" "$rustup_dir/bin/rustup" default stable
}

function install_cargo_binstall() {
	# Install cargo-binstall to speed up Rust package installations
	# cargo-binstall downloads pre-compiled binaries instead of building from source
	# See: https://github.com/cargo-bins/cargo-binstall
	
	# Determine target user (same logic as install_rust)
	local target_user
	if [[ -n ${1+x} && -n "$1" ]]; then
		target_user="$1"
	elif [[ -n ${user+x} && -n "$user" ]]; then
		target_user="$user"
	elif [[ -n ${SUDO_USER+x} && "$SUDO_USER" != "" && "$SUDO_USER" != "root" ]]; then
		target_user="$SUDO_USER"
	else
		target_user="$USER"
	fi
	
	local target_home
	target_home="$(get_home_dir "$target_user")"
	local cargo_bin="${target_home}/.cargo/bin"
	
	# Check if cargo is installed for target user
	if [ ! -f "${cargo_bin}/cargo" ]; then
		echo "Cargo is not installed for $target_user. Installing Rust first."
		install_rust "$target_user"
	fi

	# Check if cargo-binstall is already installed
	if [ -f "${cargo_bin}/cargo-binstall" ]; then
		return 0
	fi

	# Also check in cargo install list
	if sudo -H -u "$target_user" env HOME="$target_home" PATH="${cargo_bin}:$PATH" cargo install --list 2>/dev/null | grep -q "^cargo-binstall "; then
		return 0
	fi

	# Install cargo-binstall using the quick install script (downloads pre-compiled binary)
	logexec curl -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh -o /tmp/install-binstall.sh
	logexec chmod +x /tmp/install-binstall.sh
	# Run install script as target user with correct HOME and CARGO_HOME
	logexec sudo -H -u "$target_user" env HOME="$target_home" CARGO_HOME="${target_home}/.cargo" /tmp/install-binstall.sh
	rm -f /tmp/install-binstall.sh
}

function install_rust_app() {
	local appname=$1
	
	# Determine target user (same logic as install_rust)
	local target_user
	if [[ -n ${2+x} && -n "$2" ]]; then
		target_user="$2"
	elif [[ -n ${user+x} && -n "$user" ]]; then
		target_user="$user"
	elif [[ -n ${SUDO_USER+x} && "$SUDO_USER" != "" && "$SUDO_USER" != "root" ]]; then
		target_user="$SUDO_USER"
	else
		target_user="$USER"
	fi

	if [ -z "$appname" ]; then
		echo "No app name provided."
		return 1
	fi
	
	local target_home
	target_home="$(get_home_dir "$target_user")"
	local cargo_bin="${target_home}/.cargo/bin"

	# Check if cargo is installed for target user
	if [ ! -f "${cargo_bin}/cargo" ]; then
		echo "Cargo is not installed for $target_user. Installing Rust first."
		install_rust "$target_user"
	fi

	# Check if app is already installed
	if sudo -H -u "$target_user" env HOME="$target_home" PATH="${cargo_bin}:$PATH" cargo install --list 2>/dev/null | grep -q "^$appname "; then
		return 0 # Already installed
	fi

	# Install cargo-binstall first to speed up installations
	install_cargo_binstall "$target_user"

	# Use cargo binstall if available (downloads pre-compiled binaries)
	# Fall back to cargo install if binstall fails
	if [ -f "${cargo_bin}/cargo-binstall" ]; then
		# Try binstall first, fall back to cargo install if it fails
		if ! sudo -H -u "$target_user" env HOME="$target_home" PATH="${cargo_bin}:$PATH" cargo binstall --no-confirm "$appname" 2>&1; then
			logexec sudo -H -u "$target_user" env HOME="$target_home" PATH="${cargo_bin}:$PATH" cargo install "$appname"
		fi
	else
		logexec sudo -H -u "$target_user" env HOME="$target_home" PATH="${cargo_bin}:$PATH" cargo install "$appname"
	fi
}
