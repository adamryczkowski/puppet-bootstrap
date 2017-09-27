#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Deploys the n2n server on the given ssh address. It might install the N2N client on the server
as well, depending on the options. 

It will install a client if you want to deploy a DHCP server. 


Usage:

$(basename $0) <ssh addres of the server> <further options passed to n2n-server.sh>


where
 ssh addres of the server - Address to the server, including username, e.g. root@134.234.3.63
 <further options ...>    - Options passed to n2n-server.sh 


Example2:

$(basename $0) root@172.104.148.166 --debug -- --password 'secret_password' 

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

if [ -n "$n2n_server" ] || [ -n "$n2n_password" ]; then
	use_n2n=1
else
	use_n2n=0
fi 

./execute-script-remotely.sh n2n-server.sh --ssh-address $ssh_address --extra-executable n2n-client.sh --extra-executable files/n2n.patch $opts -- $all_opts
