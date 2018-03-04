#!/bin/bash
cd `dirname $0`
. ./common.sh

usage="
Installs update-all repository

The script can be run either as a root or normal user




Usage:

$(basename $0) <user-name> [--help] [--install-dir <install dir>] [--debug] [--log log]

where

 --install-dir <install dir> - Place to install the repository
 --debug                     - Flag that sets debugging mode. 
 --log                       - Path to the log file that will log all meaningful commands


Example:

$(basename $0) 
"

dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}
mypath=${0%/*}
mypath=`dir_resolve $mypath`
cd $mypath

if [ "${USER}" == "root" ]; then
	install_dir='/usr/local/lib'
else
	install_dir='$(get_home_dir)/tmp'
fi

debug=0
wormhole=0

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
	--install-dir)
	install_dir=$1
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

if [ ! -w ${install_dir} ] ; then 
	errcho "${install_dir} is not writable for ${USER}"
	exit 1
fi

install_apt_package git-core git

logmkdir "${install_dir}"

if [ -d "${install_dir}/update-all" ]; then
	logexec pushd "${install_dir}/update-all"
	logexec git pull
else
	logexec pushd "${install_dir}"
	git clone --depth 1 https://github.com/adamryczkowski/update-all
fi
logexec popd

