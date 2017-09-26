#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Deploys the R in the server on the given ssh address


Usage:

$(basename $0) <ssh addres of the server> --n2n-server <ip:port> --n2n-password <password>
             [--network-name <network name>] [--ip <nie ip address>] [--copy-from <ifname>]
             [--help] [--debug] [--log <output file>] -- [<other options passed to prepare_remote_ubuntu.sh>]


where
 ssh addres of the server - Address to the server, including username, e.g. root@134.234.3.63
 other options passed...  - All options except for the address of the server
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands
 --n2n-server <ip:port>   - IP and port of the supernode of the n2n network
 --ip                     - IP of the node
 --n2n-password           - Password of the n2n network
 --network-name           - Name of the n2n community. All edges within the same community 
                            appear on the same LAN (layer 2 network segment). 
                            Community name is 16 bytes in length. 
                            Defaults to 'My_n2n_network'
 --copy-from <ifname>     - Name of the network interface to use to derrive IP of the node.
                            Defaults to 'edge0'



Example2:

$(basename $0) --debug

"

ssh_address=$1
if [ -z "$1" ]; then
	echo "$usage"
	exit 0
fi

username=$(whoami)

n2n_name="My_n2n_network"
local_n2n_iface="edge0"

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
	--ip)
	n2n_ip=$1
	shift
	;;
	--n2n-password)
	n2n_password=$1
	shift
	;;
	--network-name)
	n2n_name=$1
	shift
	;;
	--copy-from)
	local_n2n_iface=$1
	shift
	;;
	--wormhole)
	wormhole=1
	;;
	--)
	break
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

if [ -n "$n2n_server" ] || [ -n "$n2n_password" ]; then
	use_n2n=1
else
	use_n2n=0
fi 

function guess_n2n_ip {
	local_ip=$(get_iface_ip $local_n2n_iface)
	if [ -z "$local_ip" ]; then
		exit 1
	fi
	pattern='([[:digit:]]+)\.([[:digit:]]+)\.([[:digit:]]+)\.([[:digit:]]+)'
	if [[ "$local_ip" =~ $pattern ]]; then
		new_ip=
		user=${BASH_REMATCH[4]}
		ip=${BASH_REMATCH[5]}
		port=${BASH_REMATCH[7]}
		return 0
	else

}

if [ "$use_n2n" == "1" ]; then
	if [ -z "$n2n_ip" ]; then
	
fi

./prepare_remote_ubuntu.sh $ssh_address "$@"

./execute-script-remotely.sh prepare-R-node.sh --ssh-address $ssh_address 
