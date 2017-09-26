#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Prepares peer-to-peer vpn 'n2n' server or node on


Usage:

$(basename $0) [--port <portnr>] [--no-dhcp] [--dhcp-range <ip-ip>] -- <options passed to n2n_client needed for dhcp server.>

where

 --port                   - UDP port to listen to. Defaults to 55355
                            E.g. 139.162.181.142:5000. Port must be the same as the supernode. 
 --no-dhcp                - Flag. If given, no DHCP server will be installed on the network. 
 --dhcp-range             - Range of the addresses to use in the network. 
                            Defaults to 'auto', which will randomly take 10.x.x.0/24 IP domain.
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands
 <options to n2n_client>  - You must provide password. Server address will be put automatically. 
                            You can override --ip address of the dhcp server. 


Example2:

$(basename $0) --port 5000

"

port=5535
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
	--no-dhcp)
	no_dhcp="$1"
	;;
	--dhcp-range)
	dhcp_range="$1"
	shift
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

if [ -n "$debug" ]; then
	opts="$opts --debug"
	if [ -z "$log" ]; then
		log=/dev/stdout
	else
		opts="$opts --log $log"
	fi
fi

if [ -z "$no_dhcp" ]; then
	#We need to create DHCP server. For that:
	#1. We need to generate dhcp range or get the existing one
	#2. We need to generate IP for the server
	#3. We need to install n2n client with the fixed ip for the dhcp server
	#4. We need to install the dhcp server itself

	if [ -z "$dhcp_range" ]; then
		ip_prefix=10.$((RANDOM%256)).$((RANDOM%256))
		dhcp_range="${ip_prefix}.10 ${ip_prefix}.199"
		server_ip=${ip_prefix}.1
	else
		pattern='([[:digit:]]+)\.([[:digit:]]+)\.([[:digit:]]+)\.([[:digit:]]+).([[:digit:]]+)\.([[:digit:]]+)\.([[:digit:]]+)\.([[:digit:]]+)'
		if [[ "$dhcp_range" =~ $pattern ]]; then
			new_ip_prefix1=${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}
			new_ip_prefix2=${BASH_REMATCH[5]}.${BASH_REMATCH[6]}.${BASH_REMATCH[7]}
			if [ "$new_ip_prefix1" != "$new_ip_prefix2" ]; then
				errcho "Right now we support only /24 IP domains. (It can be easily changed in the future)"
				exit 1
			fi
			ip_prefix=$new_ip_prefix1
			server_ip=${ip_prefix}.1
			dhcp_range="${ip_prefix}.${BASH_REMATCH[4]} ${ip_prefix}.${BASH_REMATCH[8]}"
		else
			errcho "dhcp-range has improper format. You must provide two IP addresses separated by something (e.g. space)"
			exit 1
		fi
	fi
	if ! ./n2n-client.sh localhost:$port --ip $server_ip  "$@" $opts; then
		errcho "Problems when installing n2n client. Exiting"
		exit 1
	fi
	
	if install_apt_package isc-dhcp-server; then
		restart_dhcp=1
	fi 
	
	if add_dhcpd_entry "${ip_prefix}.0" 255.255.255.0 $dhcp_range; then
		restart_dhcp=1
	fi
	if add_dhcpd_entry "${ip_prefix}.0" 255.255.255.0 $dhcp_range; then
		restart_dhcp=1
	fi
	if edit_dhcpd authoritative "<ON>"; then
		restart_dhcp=1
	fi
	
	if [ "$restart_dhcp" == "1" ]; then
		logexec sudo service isc-dhcp-server restart
	fi
	
fi

install_apt_package n2n

simple_systemd_service n2n_supernode  "N2N Supernode service" supernode -l ${port}

