#!/bin/bash

# ## dependency: files/n2n

cd `dirname $0`
. ./common.sh

#set -x

usage="
Prepares salt server with the clone of my repository


Usage:

$(basename $0) <server_address> [--server-key <server key>]
		[--help] [--debug] [--log <output file>]


where

 <server_address>           - Where the minion should find the server
 <server key>               - Public key of the server. 
 --debug                    - Flag that sets debugging mode. 
 --log                      - Path to the log file that will log all meaningful commands


Example2:

Will use existing DHCP server on the n2n network
$(basename $0) localhost  
"

server_key=""
server_address=$1
shift
if [ -z "$server_address" ]; then
	echo "$usage"
	exit 1
fi

if [ -z "${port}" ]; then
	echo "Cannot find UDP port of the server in ${server_address}"
	echo "$usage"
	exit 1
fi

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
	--develop)
	develop=1
	;;
	--server-key)
	server_key="$1"
	shift
	;;
	--help)
	echo "$usage"
	exit 0
	;;
	-*)
	echo "Error: Unknown option: $1" >&2
	echo "$usage" >&2
	exit 1
	;;
esac
done

install_apt_package curl curl

curl -o /tmp/bootstrap-salt.sh -L https://bootstrap.saltstack.com

if [[ "${develop}" == "1" ]];  then
   sudo sh /tmp/bootstrap-salt.sh -f -x python3 -git # (-M aby instalować serwer i -N aby NIE instalować miniona -f aby na pewno zrobić shallow clone)
else
   errcho "We do not support non-development versions atm."
   exit 1
fi

linetextfile /etc/salt/minion.d/server.conf "master: ${server_address}"

if [[ "${server_key}" != ""]]; then
   linetextfile /etc/salt/minion.d/server.conf "master_finger: '${server_key}'"   
fi

echo "Now you need to accept the minion in the server by typing down sudo salt-key -A"

exit 0








curl -o bootstrap-salt.sh -L https://bootstrap.saltstack.com
sudo sh bootstrap-salt.sh -f  -M -x python3 git develop # (-M aby instalować serwer i -N aby NIE instalować miniona -f aby na pewno zrobić shallow clone)


reset;sudo bash bootstrap-salt.sh -f  -git



Aby dodać clienta do serwera, należy

a) zainstalować klienta
b) w pliku /etc/salt/minion dodać
mater: <address to the server>
master_finger: 'e0:b5:6b:01:03:8b:00:40:71:5a:8e:60:22:52:b0:9e:fd:6d:47:af:24:57:7f:e6:ff:cc:6f:c4:3b:b7:29:64' #key of the server. Odczytuje się go `sudo salt-key --finger-all | grep master.pub | grep -E '[0-9a-f]{2}(:[0-9a-f]{2})+$' -o` na masterze

Aby stworzyć repo, należy sklonować repo w serwerze w katalogu /srv/salt
`sudo chown $USER /srv`


`git clone git@github.com:adamryczkowski/salt_repo.git /srv/salt`
`git clone https://github.com:adamryczkowski/salt_repo.git /srv/salt`
