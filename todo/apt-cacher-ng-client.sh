#!/bin/bash
cd `dirname $0`
. ./common.sh

#This script prepares apt-cacher-ng client

#syntax:
#prepare-apt-cache.sh -p|--apt-proxy <auto>|<apt-cacher-ng address together with port>

alias errcho='>&2 echo'


while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	-p|--apt-proxy)
	aptproxy="$1"
	shift
	;;
	--log)
	log=$1
	shift
	;;
	--debug)
	debug=1
	;;
	*)
	echo "Unkown parameter '$key'. Aborting."
	exit 1
	;;
esac
done

if [ -z "$aptproxy" ]; then
	echo "You must specify apt-proxy parameter." >&2
	exit 1
fi

if [ "$aptproxy" == "none" ]; then
	if ! dpkg -s apt-cacher-ng>/dev/null 2>/dev/null; then
		echo "apt-cacher-ng already removed!"
	else
		logexec sudo apt-get --yes purge apt-cacher-ng
	fi
	if [ -f /etc/apt/apt.conf.d/31apt-cacher-ng ]; then
		logexec sudo rm /etc/apt/apt.conf.d/31apt-cacher-ng
		logexec sudo apt-get update
	fi
	exit 0
fi

if [ "$aptproxy" != "auto" ]; then
	if dpkg -s apt-cacher-ng>/dev/null 2>/dev/null; then
		echo "apt-cacher-ng already installed!"
	else
		logexec sudo apt-get --yes install apt-cacher-ng
	fi
	if [ ! -f /etc/apt/apt.conf.d/31apt-cacher-ng ]; then
		$loglog
		echo "Acquire::http { Proxy \"http://$aptproxy\"; };" | sudo tee /etc/apt/apt.conf.d/31apt-cacher-ng >/dev/null
		logexec sudo apt-get update
	fi
fi

