#!/bin/bash
cd `dirname $0`

. ./common.sh

usage="
Prepares the system for the LXC-2 containers:
  adds the lxc ppa repository, and configures network bridge.


Usage:
$(basename $0) setup <internal if name, e.g. lxcbr0> 
                 [-n|--network <network domain, e.g. 10.0.14.1/24>] 
                 [--dhcprange] <dhcp range>
                 [--debug] [--log <path to logfile>]
or
$(basename $0) show|help

where

internal if name - Network interface name used by the host. Defaults to lxcbr0.
                   Defaults to lxc defaults.
 -n|--network    - Network domain e.g. 10.0.14.1/24. 
                   Defaults to whatever lxc assigns.
 --dhcprange     - Dhcp range, e.g. '10.0.14.100-10.0.14.199'. 
                   Defaults to whatever lxc assigns.
 --debug         - Flag that sets debugging mode. 
 --log           - Path to the log file that will log all meaningful commands


Example:

$(basename $0) setup lxcnet0 --network 10.0.14.1/24
"

command=$1
if [ -z "$command" ]; then
	command=help
fi

pattern='^(setup|show|help)$'
if [[ ! $command =~ $pattern ]]; then
	errcho "Unknown command: $1"
	printf "$usage"
	exit 1
fi
shift


if [ "$command" == "help" ]; then
	printf "$usage"
	exit 0
fi


if [ "$command" == "show" ]; then
	if dpkg -s lxc2 >/dev/null 2>/dev/null; then
		printf "lxc version $(lxc --version) installed."
		
		printf "\n networks list "
		lxc network list | head -n 3
		lxc network list | grep -E '(YES)' -A 1

		allnetworks=$(lxc network list | grep -E '(YES)' | grep -E '^\| ([^ ]+) +\|' -o | grep -E '[^ ^\|]+' -o)
		lxc network list | grep -E '(YES)' | grep -E '^\| ([^ ]+) +\|' -o | grep -E '[^ ^\|]+' -o | while read x; do 
			printf "Details of $x";lxc network show $x
			echo ""
		done
		exit 0
	else
		printf "lxc NOT installed."
		exit 0
	fi
fi

internalif=lxcbr0
lxcnetwork=auto
lxcdhcprange=auto
needs_restart=0

if [ $command == "setup" ]; then
	pattern='^--.*$'
	if [ -n "$1" ]; then
		if ! [[ $1 =~ $pattern ]]; then
			internalif=$1
			shift
		fi
	fi
fi

#TODO:
#dns.mode - DNS registration mode ("none" for no DNS record, "managed" for LXD generated static records or "dynamic" for client generated records)
#dns.domain - Domain to advertise to DHCP clients and use for DNS resolution

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	-n|--network)
	lxcnetwork="$1"
	shift
	;;
	--dhcprange)
	lxcdhcprange="$1"
	shift
	;;
	--log)
	log=$1
	shift
	;;
	--debug)
	debug=1
	;;
	--help)
        printf "$usage"
        exit 0
	;;
	*)
	printf "Unkown parameter '$key'. Aborting."
	exit 1
	;;
        -*)
        printf "Error: Unknown option: $1" >&2
        printf "$usage" >&2
        ;;
esac
done

if [ -n "$debug" ]; then
	if [ -z "$log" ]; then
		log=/dev/stdout
	fi
fi


if ! grep -q "root:$UID:1" /etc/subuid; then
    echo "root:$UID:1" | sudo tee -a /etc/subuid
fi
if ! grep -q "root:$UID:1" /etc/subgid; then
    echo "root:$UID:1" | sudo tee -a /etc/subgid
fi

the_ppa=ubuntu-lxc/lxd-stable
add_ppa $the_ppa
do_upgrade

#if ! grep -q "^deb .*$the_ppa" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then

#	if ! which add-apt-repository; then
#		logexec sudo apt install --yes software-properties-common 
#	fi

#	logexec sudo add-apt-repository -y ppa:ubuntu-lxc/lxd-stable
#	logexec sudo apt-get update --yes
#	logexec sudo apt-get upgrade --yes
#fi


if install_apt_package lxc2; then
	if mount |grep " /home " | grep -q btrfs; then
		logexec sudo lxd init --auto --storage-backend=btrfs
	else
		logexec sudo lxd init --auto
	fi
	needs_restart=1
fi

if [ "$lxcdhcprange" == "auto" ]; then
	lxcdhcprange=''
else
	pattern='^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\-[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
	if [[ $lxcdhcprange =~ $pattern ]]; then
		lxcdhcprange=" ipv4.dhcp.ranges=$lxcdhcprange"
	else
		errcho "Malformed dhcp range. Please use two IP addresses separated by dash, eg.: 192.168.10.100-192.168.10.199"
		exit 1
	fi
fi

if ! lxc network list >/dev/null 2>/dev/null; then
	printf "Current user added to the lxd group. For this setting to take effect, you need to logout, login and run this script again"
	exit 0
fi


if [ "$lxcnetwork" == "auto" ]; then
	lxcnetworkarg=""
else
	#Pattern for full CIDR notation. It extracts hostip.
	pattern='^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\/(3[0-2]|[12][0-9]|0?[1-9])$' 
	if [[ $lxcnetwork =~ $pattern ]]; then
		lxcnetworkarg=" ipv4.address=$lxcnetwork"
	else
		errcho "Malformed --network parameter. Please use CIDR notation to encode hostname and the network mask, like this: 192.168.10.1/24"
		exit 1
	fi
fi


if lxc network list | grep -q "$internalif" 2>/dev/null; then
	ifstate=`lxc network show "$internalif"`
	pattern='\s+managed:\sfalse'

	if [[ $ifstate =~ $pattern ]]; then
		printf "Cannot set physical network. Choose some non-existant --internalif"
		exit 10
	fi
	if [ ! -z "$lxcnetwork" ] && [ "$lxcnetwork" != "auto" ]; then
		pattern='\s+ipv4\.address:\s+([0-9./]*)'
		if [[ $ifstate =~ $pattern ]]; then
			actual_network=${BASH_REMATCH[1]}
			if [ "$actual_network" != "$lxcnetwork" ]; then
				printf "Actual network $actual_network doesn't match the intended one $lxcnetwork ! Specify different network interface or make sure networks match, or delete the $internalif network beforehand with\n    lxc network delete $internalif\nand run the script again."
				exit 11
			fi
		fi
	fi
	if [ -n "${lxcdhcprange}" ]; then
		#todo check dhcp range	
		actual_dhcp_ranges=$(lxc network get ${internalif} ipv4.dhcp.ranges)
		if [ -z "${actual_dhcp_ranges}" ]; then
			logexec lxc network set ${internalif} ${lxcdhcprange}
		else
			if [ ${actual_dhcp_ranges} != ${lxcdhcprange} ]; then
				errcho "Intended dhcp ranges $lxcdhcprange differ from the actual $actual_dhcp_ranges. Because this simple script cannot check whether the lxc dhcp ranges should be overwritten, it quits and asks you to set them manually to the desired value e.g. by using the following command:\n   lxc network set ${internalif} ipv4.dhcp.ranges ${lxcdhcprange}\nThen call this script again without the --dhcprange parameter."
				exit 1
			fi
		fi
	fi	
else
	logexec lxc network create $internalif $lxcnetworkarg ipv4.nat=true $lxcdhcprange
fi



