#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Sets up a nice desktop for a given user (or the only user)
The script must be run as a root.



Usage:

$(basename $0) <username> 

where

 <username>               - Name of the user to install all the goodies. The user must be logged in.
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands


Example:

$(basename $0) adam
"

dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}
mypath=${0%/*}
mypath=`dir_resolve $mypath`
cd $mypath


user=$1
if [ -z "$user" ]; then
	echo "$usage"
	exit 0
fi

shift
debug=0
wine=0

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
	--wine)
	wine=1
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

if [ -z "$user" ]; then
	errcho "No user!"
	echo "$usage" 
	exit 1
fi

add_ppa fixnix/netspeed
add_ppa yktooo/ppa

packages=""

if [ "$wine" == "1" ]; then
	logexec sudo dpkg --add-architecture i386 
	pushd /tmp
	wget -nc https://dl.winehq.org/wine-builds/Release.key
	sudo apt-key add Release.key
	popd
	if textfile /etc/apt/sources.d/wine.list "deb http://dl.winehq.org/wine-builds/ubuntu/ xenial main"; then
		flag_need_apt_update=1
	fi
	packages="winehq-devel"
fi

install_apt_package indicator-sound-switcher indicator-netspeed-unity redshift-gtk ${packages}

