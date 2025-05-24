#!/bin/bash
cd `dirname $0`
. ./common.sh

usage="
Prepares all fixes to the dedicated documents partition



Usage:

$(basename $0) <mount_point> <device_path> [--keyfile <path>] [--user <username>]

where

mount_point              - Path where the documents will be mounted.
e.g. /home/Adama-docs
device_path              - Path to the block device backing the encrypted storage of
the documents. E.g. /dev/disk/by-uuid/e327a906-6c6d-4447-bae1-73dc0d2da2e7

--keyfile <path>         - Path to where the keyfile is stored. Make sure it is
encrypted while you are not logged in. Best place is to put it
in an encypted home. Defaults to ~/klucz.bin
--user <username>        - Username on whos behalf you want to act. Defaults to current user.
--debug                  - Flag that sets debugging mode.
--log                    - Path to the log file that will log all meaningful commands


Example:

$(basename $0) /home/Adama-docs /dev/disk/by-uuid/e327a906-6c6d-4447-bae1-73dc0d2da2e7
"

dir_resolve()
{
	cd "$2" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}
mypath=${0%/*}
mypath=`dir_resolve $mypath`
cd $mypath


mount_point=$1
device_path=$2
shift;shift
user=$USER
keyfile=$(get_home_dir)/klucz.bin
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
	--keyfile)
	keyfile=$1
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

if [ -n "$debug" ]; then
	if [ -z "$log" ]; then
		log=/dev/stdout
	fi
fi


# 1. Make sure mounter is installed and properly configured
