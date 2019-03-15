#!/bin/bash

## dependency: files/n2n

cd `dirname $0`
. ./common.sh

#set -x

usage="
Prepares peer-to-peer vpn 'n2n' server or node on


Usage:

$(basename $0) <supernode ip:port> [--network_name <network_name>] [--ifname <ifname>]
		[--mac <mac address>] [--password <password>]
		[--help] [--debug] [--log <output file>]


where

 <ip address[:port]>        - IP address and port to the supernode.  
                              E.g. 139.162.181.142:5000. Port must be the same as the supernode. 
 --network-name             - Name of the n2n community. All edges within the same community 
                              appear on the same LAN (layer 2 network segment). 
                              Community name is 16 bytes in length. 
                              Defaults to 'My_n2n_network'
 --ifname                   - Name of the virtual network device. Defaults to 'edge0'.
 --mac                      - Sets the MAC address of the node. 
                              Without this, edge command will randomly generate a MAC address. 
                              In fact, hardcoding a static MAC address for a VPN interface is 
                              highly recommended. Otherwise, in case you restart edge 
                              daemon on a node, ARP cache of other peers will be polluted 
                              due to a newly generated MAC addess, and they will not send 
                              traffic to the node until the polluted ARP entry is evicted. 
                              Default 'auto', which will randomize MAC address.
 --name                     - Name of the service, needed if you intent to install more than one.
                              Defaults to n2n.
 --supernode-service <name> - Name of the supernode service. Required, if the supernode for this
                              VPN runs on the same host. It will make sure, that the client starts
                              after the supernode boots.
 --password                 - Password needed to join the network.  
 --ip                       - IP address in the private network of the node, or 'dhcp'. 
                              Default to 'dhcp'
 --debug                    - Flag that sets debugging mode. 
 --log                      - Path to the log file that will log all meaningful commands


Example2:

Will use existing DHCP server on the n2n network
$(basename $0)  172.104.148.166:5535 --password 'szakal' --network-name SiecAdama
"

server_address=$1
supernode_service=""
shift

if [ -z "$server_address" ]; then
	echo "$usage"
	exit 1
fi

parse_URI ${server_address}
if [ -z "${ip}" ]; then
	echo "Cannot find address of the server in ${server_address}"
	echo "$usage"
	exit 1
fi


supernode_ip=${ip}

if [ -z "${port}" ]; then
	echo "Cannot find UDP port of the server in ${server_address}"
	echo "$usage"
	exit 1
fi
supernode_port=${port}

service_name="edge"
network_name="SiecAdama"
ifname="edge0"
our_ip="dhcp"
mac="auto"

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
	--network-name)
	network_name="$1"
	shift
	;;
	--name)
	service_name="$1"
	shift
	;;
	--ifname)
	ifname="$1"
	errcho "Option --ifname is not supported now, because the init scripts that come with Ubuntu don't."
	exit 1
	shift
	;;
	--supernode-service)
	supernode_service="$1"
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
	--help)
	echo "$usage"
	exit 0
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

ubuntu_ver=$(get_ubuntu_version)
pattern='([[:digit:]]{2})([[:digit:]]{2})'
if [[ "${ubuntu_ver}" =~ $pattern ]]; then
	file_link="http://apt-stable.ntop.org/${BASH_REMATCH[1]}.${BASH_REMATCH[2]}/all/apt-ntop-stable.deb"
	file_name="n2n-$(get_ubuntu_codename)-repo.deb"
else
	errcho "Something wrong with get_ubuntu_version"
	exit 1
fi

install_apt_package_file "${file_name}" apt-ntop-stable "${file_link}" && flag_need_apt_update=1 do_update

install_apt_package n2n

config="--tun-device ${ifname}
--community ${network_name}
-k ${password}
-m ${mac}
--supernode-list ${supernode_ip}:${supernode_port}
"

if [ "${our_ip}" == "dhcp" ]; then
	config="${config} -r
-a dhcp:0.0.0.0"
else
	config="${config} -a ${our_ip}"
fi

textfile /etc/n2n/${service_name}.conf "${config}" root
if [ "$service_name" != "edge" ]; then
	set -x
	systemd_file="[Unit]
Description=n2n edge process
After=network.target syslog.target
Wants=

[Service]
Type=simple
ExecStartPre=
ExecStart=/usr/sbin/edge /etc/n2n/${service_name}.conf -f
Restart=on-abnormal
RestartSec=5

[Install]
WantedBy=multi-user.target
Alias=
"
	textfile /etc/systemd/system/${service_name}.service "${systemd_file}" root
fi
if [ "${our_ip}" == "dhcp" ]; then
	systemd_file="[Unit]
Description=DHCP Client for ${ifname}
Documentation=man:dhclient(8)
Wants=network.target
Requires=${service_name}.service
After=${service_name}.target

[Service]
Type=forking
PIDFile=/var/run/dhclient-${ifname}.pid
ExecStart=/sbin/dhclient -d ${ifname} -pf /var/run/dhclient-${ifname}.pid

[Install]
WantedBy=multi-user.target
"
	textfile /etc/systemd/system/${service_name}_dhcpd.service "${systemd_file}" root

	logexec sudo systemctl daemon-reload
	logexec sudo service ${service_name}_dhcpd restart
else
	logexec sudo service ${service_name} restart
fi
exit 0
