#!/bin/bash

## dependency: n2n-client.sh
## dependency: files/dhcpd_lease_to_slack.sh

cd `dirname $0`
. ./common.sh

usage="
Prepares softether vpn server


Usage:

$(basename $0) <server-ip>

where

 <sever-ip>               - Server address
 --port                   - Port number. Defaults to 992
 --vpn-hub                - Name of the virtual hub to connect to, defaults to 'VPN'
 --username               - User name
 --connection_name        - Connection name. Defaults to user name
 --password               - User password 
 --nicname                - Name of the network adapter. Defaults to vpn0.
 --debug                  - Flag that sets debugging mode. 
 --service                - Add as a system service under name 'softether-client-{connection-name}'
 --log                    - Path to the log file that will log all meaningful commands


Example:

./$(basename $0) 172.104.148.166 --username adam --password 12345

"

server_address=$1
shift

nicname=vpn0
password=""
username=""
vpn_hub=VPN
port=992
connection_name=""

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
	--password)
	password="$1"
	shift
	;;
	--username)
	username="$1"
	shift
	;;
	--vpn-hub)
	vpn_hub="$1"
	shift
	;;
	--nicname)
	nicname="$1"
	shift
	;;
	--port)
	port="$1"
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

if [ -z "$username" ]; then
    errcho "You must specify user name!"
    exit 1
fi

if [ -n "$connection_name" ]; then
    connection_name=$username
fi


add_ppa paskal-07/softethervpn
install_apt_package softether-vpnclient


logexec sudo vpnclient start

if ! vpncmd localhost /CLIENT /CMD AccountList | grep "${connection_name}"; then
    # Create the connection
    logexec vpncmd localhost /CLIENT /CMD AccountCreate ${connection_name} /SERVER "${server_address}:${port}" /HUB ${vpn_hub} /USERNAME ${username} /NICNAME ${nicname}
fi

logexec vpncmd localhost /CLIENT /CMD RemoteEnble /CMD AccountConnect ${connection_name}


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

