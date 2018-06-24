#!/bin/bash
cd `dirname $0`
. ./common.sh

usage="
Prepares either qbittorrent-cli



Usage:

$(basename $0) [--help] [--debug] [--log log]



Example:

$(basename $0) --debug
"

dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}
mypath=${0%/*}
mypath=`dir_resolve $mypath`
cd $mypath


debug=0

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--debug)
	debug=1
	;;
	--help)
	echo "$usage"
	exit 0
	;;
	--log)
	log=$1
	shift
	;;
	-*)
	echo "Error: Unknown option: $1" >&2
	echo "$usage" >&2
	;;
esac
done

if [ -n "$debug" ]; then
	if [ -z "$log" ]; then
		log=/dev/stdout
	fi
fi

install_apt_packages apt-transport-https ca-certificates 

release=$(get_ubuntu_codename)

add_apt_source_manual qbittorrent-cli "deb https://dl.bintray.com/fedarovich/qbittorrent-cli-debian ${release} main" https://bintray.com/user/downloadSubjectPublicKey?username=fedarovich qbittorrent-cli_Release.key

install_apt_package qbittorrent-cli

