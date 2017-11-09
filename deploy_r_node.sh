#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Deploys the R in the server on the given ssh address


Usage:

$(basename $0) <ssh addres of the server> --n2n-server <ip:port> --n2n-password <password>
             [--help] [--debug] [--log <output file>] 


where
 ssh addres of the server - Address to the server, including username, e.g. root@134.234.3.63
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands
 --n2n-server <ip:port>   - IP and port of the supernode of the n2n network
 --n2n-password           - Password of the n2n network



Example2:

$(basename $0) root@109.74.199.59  --n2n-server 172.104.148.166:5535 --n2n-password szakal --debug

"

ssh_address=$1
if [ -z "$1" ]; then
	echo "$usage"
	exit 0
fi

username=$(whoami)


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
	--n2n-server)
	n2n_server=$1
	shift
	;;
	--n2n-password)
	n2n_password=$1
	shift
	;;
	--rstudio)
	opts2="$opts2 --rstudio"
	;;
	--rstudio-server)
	opts2="$opts2 --rstudio-server"
	;;
	-*)
	echo "Error: Unknown option: $1" >&2
	echo "$usage" >&2
	exit 1
	;;
esac
done

opts=""

if [ -n "$debug" ]; then
	opts="$opts --debug"
	if [ -z "$log" ]; then
		log=/dev/stdout
	else
		opts="$opts --log $log"
	fi
fi

parse_URI $ssh_address
if [ -z "$ip" ]; then
	errcho "You must provide a valid ssh address in the first argument"
	exit 1
fi


./prepare_remote_ubuntu.sh $ssh_address --wormhole $opts

if [ -n "$n2n_server" ] && [ -n "$n2n_password" ]; then
	if [ -z "$n2n_password" ]; then
		errcho "You must provide a password to N2N somehow"
		exit 1
fi
	./deploy_n2n_client.sh $ssh_address $n2n_server --password $n2n_password $opts
fi

./execute-script-remotely.sh prepare-R-node.sh --ssh-address $ssh_address  $opts -- $opts2 
