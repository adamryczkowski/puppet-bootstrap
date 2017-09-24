#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Prepares peer-to-peer vpn 'n2n' server or node on


Usage:

$(basename $0) supernode --port <portnr> 

$(basename $0) edge <supernode ip:port> [--network_name <network_name>] [--ifname <ifname>]
		[--mac <mac address>] [--password <password>] 
		[--help] [--debug] [--log <output file>]


where

 <ip address[:port]>      - IP address and port to the supernode.  
                            E.g. 139.162.181.142:5000. Port must be the same as the supernode. 
 --network-name           - Name of the n2n community. All edges within the same community 
                            appear on the same LAN (layer 2 network segment). 
                            Community name is 16 bytes in length. 
                            Defaults to 'My_n2n_network'
 --ifname                 - Name of the virtual network device. Defaults to 'edge0'.
 --mac                    - Sets the MAC address of the node. 
                            Without this, edge command will randomly generate a MAC address. 
                            In fact, hardcoding a static MAC address for a VPN interface is 
                            highly recommended. Otherwise, in case you restart edge 
                            daemon on a node, ARP cache of other peers will be polluted 
                            due to a newly generated MAC addess, and they will not send 
                            traffic to the node until the polluted ARP entry is evicted. 
                            Default 'auto', which will randomize MAC address.
 --password               - Password needed to join the network.  
 --ip                     - IP address in the private network of the node. 
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands


Example2:

$(basename $0) supernode --port 5000

$(basename $0) edge 139.162.181.142:5000 --network_name WAMS --password 'pa\$\$word'
"

mode=$1
if [ -z "$mode" ]; then
	echo "$usage"
	exit 0
fi

if [ "$mode" != "supernode" ] && [ "$mode" != "edge" ]; then
	echo "$usage"
	exit 1
fi
shift

if [[ "$mode" == "supernode" ]]; then
	port=5000
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
		--port)
		port="$1"
		shift
		;;
		-*)
		echo "Error: Unknown option: $1" >&2
		echo "$usage" >&2
		exit 1
		;;
	esac
	done
	
	install_apt_package n2n

	simple_systemd_service n2n_supernode  "N2N Supernode service" supernode -l ${port}
	exit 0
fi

server_address=$1
shift

if [ -z "$server_address" ]; then
	echo "$usage"
	exit 1
fi

parse_URI ${server_address}
if [ -z "${ip}" ]; then
	echo "Cannot find address of the server in ${server_address}"
	exit 1
fi
supernode_ip=${ip}

if [ -z "${port}" ]; then
	echo "Cannot find UDP port of the server in ${server_address}"
	exit 1
fi
supernode_port=${port}

network_name="My_n2n_network"
ifname="edge0"

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
	--network-name)
	network_name="$1"
	shift
	;;
	--ifname)
	ifname="$1"
	shift
	;;
	--mac)
	mac="$1"
	shift
	;;
	--password)
	password="$1"
	shift
	;;
	--ip)
	our_ip="$1"
	shift
	;;
	-*)
	echo "Error: Unknown option: $1" >&2
	echo "$usage" >&2
	exit 1
	;;
esac
done

if [ -n "$debug" ]; then
	if [ -z "$log" ]; then
		log=/dev/stdout
	fi
	external_opts="--debug"
fi


if [[ "$mac" == "auto" ]]; then
	mac=$(random_mac 02) 
fi

if [ -z "$password" ]; then
	errcho "No password given. Without the password the service cannot run.\nThe password will be saved in plaintext in /etc/default/n2n with restrictive read permissions."
	exit 1
fi

if [ -z "${our_ip}" ]; then
	errcho "You must provide a static IP with the '--ip <ip>' argument."
	exit 1
fi

install_apt_package n2n

if edit_bash_augeas /etc/default/n2n N2N_COMMUNITY ${network_name}; then
	restart=1
fi 
if edit_bash_augeas /etc/default/n2n N2N_KEY ${password}; then
	restart=1
fi
if edit_bash_augeas /etc/default/n2n N2N_SUPERNODE ${supernode_ip}; then
	restart=1
fi
if edit_bash_augeas /etc/default/n2n N2N_SUPERNODE_PORT ${supernode_port}; then
	restart=1
fi
if edit_bash_augeas /etc/default/n2n N2N_IP ${our_ip}; then
	restart=1
fi
if edit_bash_augeas /etc/default/n2n N2N_EDGE_CONFIG_DONE yes; then
	restart=1
fi
 

if [ "$restart" == "1" ]; then
	logexec sudo service n2n restart
fi
