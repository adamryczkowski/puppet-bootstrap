#!/bin/bash

## dependency: dhcp-server.sh
## dependency: softether-client.sh

cd `dirname $0`
. ./common.sh

usage="
Prepares softether vpn server


Usage:

$(basename $0) [--port <portnr>] [--https] [--dns] [--telnets] [--icmp] [--dhcp-server] [--dhcp-range <ip-ip>]

where

--port <portnr>          - TCP port to listen to. Defaults to 5555
--https                  - Flag. If given, port 443 will also be opened and used.
--telnets                - Flag. If given, port 992 will also be opened and used.
--dns                    - Flag. If given, traffic over DNS will be used, and port 53 opened.
--icmp                   - Flag. If given, traffic over ping will be used.
--dhcp-server            - Flag. If given, internal dhcp server will be used
--dhcp-range             - Range of the addresses to use in the network.
Defaults to 'auto', which will randomly take 10.x.x.0/24 IP domain.
Relevant only whith --dhcp-server option.
--ifname                 - Name of the virtual network device. Defaults to 'se'.
--service-name           - Name of the server service, needed if you intent to install more than one.
Defaults to softether-server.
--password               - Password for the management
--user                   - Adds user with this name
--userpassword           - Password for the user.
--debug                  - Flag that sets debugging mode.
--log                    - Path to the log file that will log all meaningful commands


Example:

./$(basename $0) --https --dns --telnets --icmp --password szakal --dhcp-server

"
server_service_name="softether-server"
our_ip="dhcp"
port=5555
ifname='se'
use_https=0
use_telnets=0
use_dns=0
use_icmp=0
ude_dhcp_server=0
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
	--https)
	use_https=1
	;;
	--telnets)
	use_telnets=1
	;;
	--dns)
	use_dns=1
	;;
	--icmp)
	use_icmp=1
	;;
	--dhcp-server)
	use_dhcp_server=1
	;;
	--ifname)
	ifname="$1"
	shift
	;;
	--password)
	password="$1"
	shift
	;;
	--user)
	vpnuser="$1"
	shift
	;;
	--userpassword)
	vpnuserpassword="$1"
	shift
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

if ! [ -n "${vpnuser}" ] && [ -n "${vpnuserpassword}" ]; then
   if ! [ -n "${vpnuser}" ] && [ -n "${vpnuserpassword}" ]; then
      errcho "You must provide either both --user and --userpassword or none"
      exit 1
   fi
fi

if [[ "$use_dhcp_server" == "0" && "$dhcp_range" == "" ]] ; then
	errcho "Cannot add --dhcp-range if no dhcp server is in use. Add --dhcp-server option."
	exit 1
fi
if [ -z "$password" ]; then
	errcho "--pasword is an obligatory parameter"
	exit 1
fi

add_ppa paskal-07/softethervpn
install_apt_package softether-vpnserver

logexec vpncmd /SERVER localhost /CMD ServerPasswordSet "${password}" /CMD Hub VPN /CMD SecureNATEnable

echo "${password}" | vpncmd /SERVER localhost /CMD HubCreate VPN /PASSWORD "${password}"

# SecureNAT collides with the dhcp server
# logexec vpncmd /SERVER localhost /HUB:VPN /CMD  SecureNATEnable

logexec vpncmd /SERVER localhost /HUB:VPN /CMD UserCreate adam /GROUP "" /REALNAME adam /NOTE ""

logexec vpncmd /SERVER localhost /HUB:VPN /CMD UserPasswordSet adam /PASSWORD szakal

logexec vpncmd /SERVER localhost /HUB:VPN /CMD UserPasswordSet adam /PASSWORD szakal

#IPsecEnable #keep hitting yes and setup shared key for LT2P
#
##Optional enable openvpn protocol
#ServerCertRegenerate <your_server_IP OR domain>
#ServerCertGet ~/cert.cer
#SstpEnable yes
#OpenVpnEnable yes /PORTS:1194


#install_apt_package curl
#last_version=$(get_latest_github_release_name SoftEtherVPN/SoftEtherVPN)
#link="https://github.com/SoftEtherVPN/SoftEtherVPN/archive/${last_version}.tar.gz"
#get_git_repo https://github.com/SoftEtherVPN/SoftEtherVPN.git /opt SoftEther

#install_apt_packages curl cmake build-essential libssl-dev zlib1g-dev libreadline-dev

#if ! which vpncmd>/dev/null; then
#   logmkdir "/opt/SoftEther" adam
#   logmkdir "/opt/SoftEther/build" adam
#   pushd "/opt/SoftEther/build"
#   logexec cmake ..
#   logexec make -j
#   logexec sudo make install
#fi

exit 1
