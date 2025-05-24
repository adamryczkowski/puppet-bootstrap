#!/bin/bash

# This script contains functions to manage pip packages and virtual environments.

function is_pipx_installed {
  command -v pipx &> /dev/null
}

function install_pipx {
  install_apt_package pipx
}

function install_pipx_command {
  local library=$1
  if [ -z "$library" ]; then
    echo "No library name provided."
    return 1
  fi

  if ! command -v pipx &> /dev/null; then
    echo "pipx is not installed. Please install pipx first."
    install_pipx
  fi

  if pipx list | grep -q "$library"; then
    return 0 # Already installed
  fi

  logexec pipx install "$library"
}