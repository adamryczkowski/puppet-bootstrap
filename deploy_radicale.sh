#!/bin/bash
cd `dirname $0`
. ./common.sh

## dependency: prepare_radicale.sh

usage="
Deploys calendar server radicale on the given ssh address


Usage:

$(basename $0) <ssh addres of the server> -- [options forwarded to prepare_radicale]
[--help] [--debug] [--log <output file>]


where
ssh addres of the server      - Address to the server, including username, e.g. root@134.234.3.63
--debug                       - Flag that sets debugging mode.
--log                         - Path to the log file that will log all meaningful commands

prepare_radicale supports the following options:
--cal-user <user>:<password>  - Username and password of first calendar user



Example2:

./$(basename $0) root@109.74.199.59 -- --cal_user adam:password

"

ssh_address=$1
if [ -z "$1" ]; then
	echo "$usage"
	exit 0
fi

username=$(whoami)
user=auto
deb_folder=auto
install_lib=auto
opts=""
opts2=""



while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--debug)
	debug=1
	;;
	--log)
	log=$1
	shift
	;;
	--help)
	echo "$usage"
	exit 0
	;;
	--)
	opts2=$@
	break
	;;
	-*)
	echo "Error: Unknown option: $1" >&2
	echo "$usage" >&2
	exit 1
	;;
esac
done


if [ -n "$debug" ]; then
	opts2="$opts2 --debug"
	if [ -z "$log" ]; then
		log=/dev/stdout
	else
		opts2="$opts2 --log $log"
	fi
fi

parse_URI $ssh_address
if [ -z "$ip" ]; then
	errcho "You must provide a valid ssh address in the first argument"
	exit 1
fi

./execute-script-remotely.sh prepare_radicale.sh --step-debug --ssh-address $ssh_address -- $opts2 --debug
