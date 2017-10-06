#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Installs locally the IMGW VPN


Usage:

$(basename $0)  <username>@<host> --password <password> 
		[--help] [--debug] [--log <output file>]


where
 <username>@<host>        - Username and the address of the VPN gateway
 --password               - Password for the VPN (in open text)
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands


Example2:

$(basename $0) https://aryczkowski@vpn.imgw.pl --password Qwerty12345 --debug
"

if [ -z "$1" ]; then
	echo $usage
	exit 0
fi
vpn_address=$1
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
	--password)
	password=$1
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

if [ -z "$password" ]; then
	errcho "You must provide password"
	exit 1
fi

parse_URI vpn_address
            proto=${BASH_REMATCH[2]}
            user=${BASH_REMATCH[4]}
            ip=${BASH_REMATCH[5]}
            port=${BASH_REMATCH[7]}

if [ -z "$proto" ]; then
	proto='ssh'
fi
if [ -z "$user" ]; then
	errcho "You must provide username for the VPN"
	exit 1
fi
if [ -z "$ip" ]; then
	ip="vpn.imgw.pl"
fi

install_apt_package openconnect openconnect

textfile /etc/openconnect/password ${password}

prg="/bin/bash -c '/bin/cat /etc/openconnect/password | $(which openconnect) ${proto}://${ip} -u ${user} --passwd-on-stdin'"

simple_systemd_service IMGW_VPN "VPN of IMGW on ${ip}" "${prg}"

