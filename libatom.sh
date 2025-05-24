#!/bin/bash

function install_atom_packages() {
	local package=$1
	atom
	if which apm >/dev/null; then
		if ! apm list | grep -q -F "$1"; then
			logexec apm install $1
		fi
	fi
}

function install_atom() {
	add_apt_source_manual atom "deb [arch=amd64] https://packagecloud.io/AtomEditor/atom/any/ any main" https://packagecloud.io/AtomEditor/atom/gpgkey atom.key
	install_apt_packages atom
}

function atom_exists() {
	which apm >/dev/null
}
