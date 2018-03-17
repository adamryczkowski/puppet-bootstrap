#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Deploys the N2N client on the given ssh address


Usage:

$(basename $0) <ssh addres of the server> <options passed to n2n-client>
             [--help] [--debug] [--log <output file>] 


where
 ssh addres of the server - Address to the server, including username, e.g. root@134.234.3.63
 other options passed...  - Options passed to n2n-client. Be sure to include password 
                            and check network-name
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands



Example2:

$(basename $0) root@178.79.188.145 172.104.148.166:5535 --password szakal --debug 

"

ssh_address=$1
if [ -z "$1" ]; then
	echo "$usage"
	exit 0
fi
shift

all_opts="$@"
opts=""


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
	opts="$opts --log $log"
	shift
	;;
	--help)
		echo "$usage"
		exit 0
	;;
	-*)
	break
	;;
esac
done

if [ -n "$debug" ]; then
	opts="$opts --debug"
	if [ -z "$log" ]; then
		log=/dev/stdout
	fi
fi

parse_URI $ssh_address
if [ -z "$ip" ]; then
	errcho "You must provide a valid ssh address in the first argument"
	exit 1
fi


./execute-script-remotely.sh n2n-client.sh --ssh-address $ssh_address  --extra-executable files/n2n $opts -- $all_opts
