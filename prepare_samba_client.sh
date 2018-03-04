#!/bin/bash
cd `dirname $0`
. ./common.sh

usage="
Creates client for samba server

The script must be run as a root.




Usage:

$(basename $0) <server-address> <share-name> <mount-place> 
               [--user <user>] [--noauto] [--password-credentials <username>;<password>] [--nomount] 
               [--help] [--debug] [--log log]

where

 device-address           - Address of the server (e.g. IP address)
 share-name               - Share name, as published by the server
 mount-place              - Place where the share will be mounted. The directory will be created, if not existing
 --user <user>            - What user shall be the owner of the share?
 --password-credentials   - File that lists password credentials in the format <username>;<password>,
                            e.g. adam;szakal
 --noauto                 - If set, the mount will not be mounted during boot time
 --nomount                - If set, the mount will not be mounted now
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands


Example:

$(basename $0) 192.168.10.2 other /media/adam-minipc/other --password-credentials adam;szakal
"

dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}
mypath=${0%/*}
mypath=`dir_resolve $mypath`
cd $mypath



device_address=$1
share_name=$2
mount_place=$3
shift;shift;shift
auto=1
mount=1
user=root

debug=0

if [ -z "${mount_place}" ]; then
	echo "$usage"
	exit 0
fi

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
	--password-credentials)
	password_credentials=$1
	shift
	;;
	--user)
	user=$1
	shift
	;;
	--noauto)
	auto=0
	;;
	--nomount)
	mount=0
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

if ! sudo -n true 2>/dev/null; then
	errcho "User $USER doesn't have admin rights"
	exit 1
fi

if ! is_host_up $device_address; then
	if [ "${mount}" == "1" ]; then
		errcho "Host ${device_address} is down"
	fi
fi

install_apt_package cifs-utils

if [ -n "${password_credentials}" ]; then
	pattern='^([^;]+);(.*)$'
	if [[ "$password_credentials" =~ $pattern ]]; then
		contents="username=${BASH_REMATCH[1]}
password=${BASH_REMATCH[2]}"
		textfile /etc/samba/user "${contents}"
	fi
fi

if [ "${auto}" == "1" ]; then
	auto=""
elif [ "${auto}" == "0" ]; then
	auto="noauto"
else
	exit 254
fi

logmkdir ${mount_place} ${user}
smb_share_client ${device_address} ${share_name} ${mount_place} /etc/samba/user ${auto} 

if [ "${mount}" == "1" ]; then
	if ! mount | grep ${mount_place} >/dev/null; then
		mount ${mount_place}
	fi
fi
