#!/bin/bash

## dependency: n2n-client.sh
## dependency: files/dhcpd_lease_to_slack.sh

cd `dirname $0`
. ./common.sh

usage="
Installs and configures dhcp server


Usage:

$(basename $0) <ifname> --dhcp-range <ip-ip> [--ip <ip>]

where

 --dhcp-range             - Range of the addresses to use in the network. 
                            Defaults to 'auto', which will randomly take 10.x.x.0/24 IP domain.
 --ip                     - IP Address to set.
 --ifname                 - Name of the network device that dhcp will listen to.
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands
 <options to n2n_client>  - You must provide password. Server address will be put automatically. 
                            You can override --ip address of the dhcp server. 


Example2:

./$(basename $0) vpn_vpn --dhcp-range 192.168.30.100-192.168.30.199

"

if [ "$1" == "" ]; then
	echo "$usage" >&2
	exit 1
fi

if [ "$1" == "--help" ]; then
	echo "$usage" >&2
	exit 1
fi

ifname="$1"
shift


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
server_ip=$(get_iface_ip $ifname)
pattern='([[:digit:]]+)\.([[:digit:]]+)\.([[:digit:]]+)\.([[:digit:]]+)'
if [[ "$server_ip" =~ $pattern ]]; then
   server_prefix=${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}
else
   server_prefix=""
fi
if [ -z "$dhcp_range" ]; then
   if [ -z "$server_prefix" ]; then
   	ip_prefix=10.$((RANDOM%256)).$((RANDOM%256))
   	server_ip=${ip_prefix}.1
   else
      ip_prefix=${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}
   fi
	dhcp_range="${ip_prefix}.100 ${ip_prefix}.199"
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
		if [[ "${ip_prefix}" != "${server_prefix}" ]]; then
		   errcho "Warning: server ${server_ip} is on different domain than the dhcp range!"
		fi

		server_ip=${ip_prefix}.1
		dhcp_range="${ip_prefix}.${BASH_REMATCH[4]} ${ip_prefix}.${BASH_REMATCH[8]}"
	else
		errcho "dhcp-range has improper format. You must provide two IP addresses separated by something (e.g. space)"
		exit 1
	fi
fi

if install_apt_package isc-dhcp-server; then
	restart_dhcp=1
	logexec sudo ln -s /etc/apparmor.d/usr.sbin.dhcpd /etc/apparmor.d/disable
	logexec sudo apparmor_parser -R /etc/apparmor.d/usr.sbin.dhcpd
fi 
set -x
linetextfile /etc/dhcp/dhcpd.conf "include \"/etc/dhcp/dhcpd_lease_to_slack.conf\";"
contents="on commit {
set ClientIP = binary-to-ascii(10, 8, \".\", leased-address);
set ClientMac = binary-to-ascii(16, 8, \":\", substring(hardware, 1, 6));
set ClientName = pick-first-value ( option fqdn.hostname, option host-name );
log(concat(\"Commit: IP: \", ClientIP, \" Mac: \", ClientMac));
execute(\"/etc/dhcp/dhcpd_lease_to_slack.sh\", \"commit\", ClientIP, ClientMac, ClientName);
}"
textfile /etc/dhcp/dhcpd_lease_to_slack.conf "$contents" root
install_script ${DIR}/files/dhcpd_lease_to_slack.sh /etc/dhcp/dhcpd_lease_to_slack.sh root

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
	logexec sudo service isc-dhcp-server restart #Make sure the dhcp starts AFTER supernode and its client
fi

actual_server_ip=$(get_iface_ip $ifname)

if [ "${actual_server_ip}" != "${server_ip}" ]; then
   sudo ifcon

