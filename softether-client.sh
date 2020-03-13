#!/bin/bash

cd `dirname $0`
. ./common.sh

usage="
Prepares softether vpn server


Usage:

$(basename $0) <server-ip> --username <username> --password <plaintext password> [--ip <static_ip>] [--vpn-hub <hub name>]
                   [--connection_name <name>] [--nicname <vpn adapter name>] [--port <Server's IP port>]

where

 <sever-ip>               - Server address
 --port                   - Port number. Defaults to 992
 --vpn-hub                - Name of the virtual hub to connect to, defaults to 'VPN'
 --username               - User name (defaults to hostname)
 --ip                     - Static ip to use (good for dhcp servers)
 --connection_name        - Connection name. Defaults to user name
 --password               - User password. In plaintext, so make sure this command is not placed in the history
 --nicname                - Name of the network adapter. Defaults to vpn0.
 --debug                  - Flag that sets debugging mode. 
 --service                - Add as a system service under name 'softether-client-{connection-name}'
 --log                    - Path to the log file that will log all meaningful commands


Example:

./$(basename $0) 172.104.148.166 --username adam --password 12345

"

if [ "$1" == "" ]; then
	echo "$usage" >&2
	exit 1
fi

if [ "$1" == "--help" ]; then
	echo "$usage" >&2
	exit 1
fi

server_address=$1
shift

nicname=vpn
password=""
username="$(hostname)"
ip="dhcp"
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
	--connection_name)
	connection_name="$1"
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
	--ip)
	ip="$1"
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

if [ -z "$connection_name" ]; then
    connection_name=$username
fi

if [ ! "${ip}" == "dhcp" ]; then
   pattern='^([[:digit:]]+)\.([[:digit:]]+)\.([[:digit:]]+)\.([[:digit:]]+)$'
   if [[ ! "$ip" =~ $pattern ]]; then
      errcho "Wrong format of the ip!"
      exit 1
   fi
fi

add_ppa paskal-07/softethervpn
install_apt_package softether-vpnclient


logexec sudo vpnclient start

if ! vpncmd localhost /CLIENT /CMD AccountList | grep -q "VPN Connection Setting Name |${connection_name}"; then
    # Create the connection
    if ! vpncmd localhost /CLIENT /CMD NicList | grep -q "Virtual Network Adapter Name|${nicname}"; then
      logexec vpncmd localhost /CLIENT /CMD NicCreate ${nicname}
    fi
    logexec vpncmd localhost /CLIENT /CMD AccountCreate ${connection_name} /SERVER:"${server_address}:${port}" /HUB:${vpn_hub} /USERNAME:${username} /NICNAME:${nicname}
    logexec vpncmd localhost /CLIENT /CMD AccountPasswordSet ${connection_name} /PASSWORD:${password} /TYPE:standard
fi

#logexec sudo vpncmd localhost /CLIENT /CMD accountconnect ${connection_name}

textfile /etc/systemd/system/softether_${connection_name}_client.service "[Unit]
    Description=SoftEther ${connection_name} Client
    After=softether_client.service
    Requires=softether_client.service
    
[Service]
    Type=oneshot
    ExecStart=/bin/bash /usr/local/lib/softether/start_${connection_name}_vpn.sh
    ExecStop=/usr/bin/vpncmd localhost /CLIENT /CMD accountdisconnect ${connection_name}
    ExecStop=/bin/bash -c \"ifconfig vpn_${nicname} down\"
    RemainAfterExit=yes
[Install]
    WantedBy=multi-user.target" root
    

textfile /etc/systemd/system/softether_client.service "[Unit]
    Description=SoftEther Client service
    After=network.target auditd.service
    
[Service]
    Type=forking
    ExecStart=/usr/bin/vpnclient start
    ExecStop=/usr/bin/vpnclient stop
    KillMode=process
    Restart=on-failure
    
[Install]
    WantedBy=multi-user.target" root

#install_file files/softether_svc /etc/systemd/system/softether_${connection_name}_client.service root

logmkdir /usr/local/lib/softether root

if [ "${ip}" == "dhcp" ]; then
   textfile /usr/local/lib/softether/start_${connection_name}_vpn.sh "#!/bin/sh
sudo /usr/bin/vpncmd localhost /CLIENT /CMD accountconnect ${connection_name}
sudo dhclient vpn_${nicname}" root
else
   textfile /usr/local/lib/softether/start_${connection_name}_vpn.sh "#!/bin/sh
sudo /usr/bin/vpncmd localhost /CLIENT /CMD accountconnect ${connection_name}
sudo ifconfig vpn_${nicname} ${ip}
if service --status-all | grep -Fq 'isc-dhcp-server'; then    
  sudo systemctl restart isc-dhcp-server.service
fi" root
fi

logexec sudo systemctl daemon-reload

logexec sudo systemctl enable softether_client.service
logexec sudo systemctl enable softether_${connection_name}_client.service

logexec sudo systemctl stop softether_client.service
logexec sudo systemctl start softether_client.service
logexec sudo systemctl stop softether_${connection_name}_client.service
logexec sudo systemctl start softether_${connection_name}_client.service

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

