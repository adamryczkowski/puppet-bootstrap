#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Just a wrapper around apt install <packages>


Usage:

$(basename $0)  [package list]


Example2:

$(basename $0) build-essential python

"


if [ "$1" == "--help" ]; then
	echo "$usage" >&2
	exit 0
fi

install_apt_packages $@
