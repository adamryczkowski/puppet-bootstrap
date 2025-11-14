#!/bin/bash

# This script contains functions to manage pip packages and virtual environments.

function is_pipx_installed() {
	command -v pipx &> /dev/null
}

function install_pipx() {
	# Ensure venv capability and pipx itself
	install_apt_packages python3-venv pipx
	# Make sure user's PATH picks up pipx shims (~/.local/bin)
	add_path_to_bashrc "$HOME/.local/bin"
}

function install_pipx_command() {
	local library=$1
	local name=$1
	if [ -z "$library" ]; then
		echo "No library name provided."
		return 1
	fi

	if ! command -v pipx &> /dev/null; then
		echo "pipx is not installed. Please install pipx first."
		install_pipx
	fi

	# Ensure python venv module is available on Debian/Ubuntu
	if ! python3 -c 'import venv' 2>/dev/null; then
		install_apt_packages python3-venv
	fi

	# Make sure user's PATH contains ~/.local/bin (pipx default) and set up shell PATH hints
	logexec pipx ensurepath || true
	add_path_to_bashrc "$HOME/.local/bin"

	# Prepare pattern that matches prefix "^git+https" and capturing the last folder as a package name, example: git+https://github.com/adamryczkowski/bright
	pattern='^git\+https:\/\/[^\/]+\/[^\/]+\/([^\/]+)$'
	if [[ "$library" =~ $pattern ]]; then
		name="${BASH_REMATCH[1]}" # Extract the package name from the URL
	fi

	# Use a stable output format to check if already installed
	if pipx list --short | grep -Fxq "$name"; then
		return 0 # Already installed
	fi

	# Try pipx first; on failure, fall back to apt for known packages
	if ! logexec pipx install "$library"; then
		case "$name" in
			tldr)
				install_apt_packages tldr-py
				;;
			dtrx)
				install_apt_packages dtrx
				;;
			magic-wormhole|wormhole)
				install_apt_packages magic-wormhole
				;;
			*)
				# Do not fail the whole run on pipx errors for unknown packages
				errcho "pipx failed to install ${library}; continuing without it"
				;;
		esac
	fi

	return 0
}
