#!/bin/bash
cd `dirname $0`

. ./common.sh

#Configures lxc-net on the host. The script is compatible with Ubuntu 14.04 and lxc1.

#syntax:
#configure-lxc [-i|--internalif] <internal if name, e.g. lxcbr0>  [-n|--network <network domain, e.g. 10.0.14.1/24>] [--dhcprange] <dhcp range, e.g. '10.0.14.3,10.0.14.254' [--usermode]
# -i|--internalif - internal if name, e.g. lxcbr0
# -n|--network network domain e.g. 10.0.14.1/24
# --dhcprange - dhcp range, e.g. '10.0.14.3,10.0.14.254' 
# --usermode-user - if provided, usermode containers will be setup for this user and the user will get all necessary privileges granted
internalif=auto
lxchostip=auto
lxcnetwork=auto
lxcdhcprange=auto
usermode=0
needsrestart=0
user=`whoami`

#TODO:
#dns.mode - DNS registration mode ("none" for no DNS record, "managed" for LXD generated static records or "dynamic" for client generated records)
#dns.domain - Domain to advertise to DHCP clients and use for DNS resolution

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--usermode-user)
	user=$1
	usermode=1
	shift
	;;
	-i|--internalif)
	internalif="$1"
	shift
	;;
	-h|--hostip)
	lxchostip="$1"
	shift
	;;
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
	*)
	echo "Unkown parameter '$key'. Aborting."
	exit 1
	;;
esac
done

. ./common.sh

the_ppa=ubuntu-lxc/lxd-stable
if ! grep -q "^deb .*$the_ppa" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
	logexec sudo add-apt-repository -y ppa:ubuntu-lxc/lxd-stable
	logexec sudo apt-get update --yes
fi
if ! dpkg -s lxc2 >/dev/null 2>/dev/null; then
	logexec sudo apt-get --yes install lxc2
	if mount |grep " /home " | grep -q btrfs; then
		logexec sudo lxd init --auto --storage-backend=btrfs
	else
		logexec sudo lxd init --auto 
	fi
else
	logexec sudo apt-get upgrade --yes
fi

if [ "$lxcnetwork" == "auto" ]; then
	lxcnetwork=""
else
	lxcnetwork=" ipv4.address=$lxcnetwork"
fi

if [ "$lxcdhcprange" == "auto" ]; then
	lxcdhcprange=""
else
	lxcdhcprange=" ipv4.dhcp.ranges=$lxcdhcprange"
fi

sudo lxc network list | grep -q "$internalif" 

if [ $? -eq 0 ]; then
	ifstate=`sudo lxc network show "$internalif"`
	pattern='\s+managed:\sfalse'

	if [[ $ifstate =~ $pattern ]]; then
		echo "Cannot set physical network. Choose some non-existant --internalif"
		exit 10
	fi
	if ! -z "$lxcnetwork"; then
		pattern='\s+ipv4\.address:\s+([0-9./]*)'
		if [[ $ifstate =~ $pattern ]]; then
			actual_network=${BASH_REMATCH[1]}
			if [ "$actual_network" != "$lxcnetwork" ]; then
				echo "Actual network $actual_network doesn't match the itended one $lxcnetwork ! Specify different network interface or make sure networks match"
				exit 11
			fi
		fi
	fi
	#todo check dhcp range	
else
	logexec sudo lxc network create $internalif $lxcnetwork $lxcdhcprange
fi

#staticleases=/etc/lxc/static_leases
#
#if [ ! -d /etc/lxc ]; then
#	logexec sudo mkdir -p /etc/lxc
#fi
#if [ ! -f $staticleases ]; then
#	logexec sudo touch $staticleases
#fi

#logexec lxc network set $internalif set raw.dnsmasq hostsfile=$staticleases

if [ "$usermode" -eq 1 ]; then
	logexec sudo usermod -aG lxd $user
	logexec sudo chown -R $user .config/lxc
fi


if [ "$needsrestart" -eq 1 ]; then
	echo "You need to log off the current session!"
	exit -1
fi
