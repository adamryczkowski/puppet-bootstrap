#!/bin/bash
cd `dirname $0`
. ./common.sh

usage="
Installs update-all repository

The script can be run either as a root or normal user




Usage:

$(basename $0) --user <username> [--help] [--install-dir <install dir>] [--debug] [--log log]

where

--install-dir <install dir> - Place to install the repository
--user <username>           - Username to install update to its ~/tmp/update-all. Defaults to the
current user.
--puppet-bootstrap          - Clone also puppet-bootstrap
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

puppet_bootstrap=0
debug=0
wormhole=0
user=${USER}

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
	--puppet-bootstrap)
	puppet_bootstrap=1
	;;
	--log)
	log=$1
	shift
	;;
	--install-dir)
	install_dir=$1
	shift
	;;
	--user)
	user=$1
	shift
	;;
    -*)
    echo "Error: Unknown option: $1" >&2
    echo "$usage" >&2
    ;;
esac
done


if [ "${user}" == "root" ]; then
	install_dir="/usr/local/lib"
else
	install_dir="$(get_home_dir ${user})/tmp"
fi


if [ -n "$debug" ]; then
	if [ -z "$log" ]; then
		log=/dev/stdout
	fi
fi

logmkdir "${install_dir}" ${user}

if [ ! -w ${install_dir} ] ; then
	errcho "${install_dir} is not writable for ${user}"
	exit 1
fi

install_apt_package git-core git

if [ -d "${install_dir}/update-all" ]; then
	logexec pushd "${install_dir}/update-all"
	logexec git pull
else
	logexec pushd "${install_dir}"
	git clone --depth 1 https://github.com/adamryczkowski/update-all
fi

if [ "${puppet_bootstrap}" == "1" ]; then
	if [ -d "${install_dir}/puppet-bootstrap" ]; then
		logexec pushd "${install_dir}/puppet-bootstrap"
		logexec git pull
	else
		logexec pushd "${install_dir}"
		git clone --depth 1 https://github.com/adamryczkowski/puppet-bootstrap
	fi
fi

logexec popd
