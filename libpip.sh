#!/bin/bash

# This script contains functions to manage pip packages and virtual environments.

function is_pipx_installed() {
	command -v pipx &> /dev/null
}

function install_pipx() {
	install_apt_package pipx
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

	# Prepare pattern that matches prefix "^git+https" and capturing the last folder as a package name, example: git+https://github.com/adamryczkowski/bright
	pattern='^git\+https:\/\/[^\/]+\/[^\/]+\/([^\/]+)$'
	if [[ "$library" =~ $pattern ]]; then
		name="${BASH_REMATCH[1]}" # Extract the package name from the URL
	fi

	if pipx list | grep -q "\^    - $name\$"; then
		return 0 # Already installed
	fi

	logexec pipx install "$library"
}
