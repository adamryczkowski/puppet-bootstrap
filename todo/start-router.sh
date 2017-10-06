#!/bin/bash
cd `dirname $0`
. ./common.sh


# syntax:
# start-router --ext-if <external if>  [--int-if <internal if>] [--host-ip <lxc host ip>] [--network <network, e.g. 192.168.13.0/24>]
debug=0



dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}
mypath=${0%/*}
mypath=`dir_resolve $mypath`
cd $mypath


network=""
INTIF=""
lxchostip=""

if [ ! -d "$gemcache" ]; then
	gemcache=
fi

while [[ $# > 0 ]]
do
key="$1"
shift
case $key in
	-d|--debug)
	debug=1
	;;
	--ext-if)
	EXTIF="$1"
	shift
	;;
	--int-if)
	INTIF="$1"
	shift
	;;
	--host-ip)
	lxchostip="$1"
	shift
	;;
	--log)
	log="$1"
	shift
	;;
	--network)
	network="$1"
	shift
	;;
	*)
	echo "Unkown parameter '$key'. Aborting."
	exit 1
	;;
esac
done

if [ -z "$EXTIF" ]; then
	errcho "Cannot find obligatory  --ext-if argument"
	exit 1
fi


if [ -z "$network" ]; then
	network=`augtool -L -A --transform "Shellvars incl /etc/default/lxc-net" get "/files/etc/default/lxc-net/LXC_NETWORK" | sed -En 's/\/.* = \"?([^\"]*)\"?$/\1/p'`
fi

if [ -z "$INTIF" ]; then
	INTIF=`augtool -L -A --transform "Shellvars incl /etc/default/lxc-net" get "/files/etc/default/lxc-net/LXC_BRIDGE" | sed -En 's/\/.* = \"?([^\"]*)\"?$/\1/p'`
fi


if [ -z "$lxchostip" ]; then
	lxchostip=`ifconfig $EXTIF | grep 'inet addr:' | cut -d: -f2 | awk '{print $1}'`
fi















#echo -e "\n\nLoading simple rc.firewall-iptables version $FWVER..\n"
DEPMOD=/sbin/depmod
MODPROBE="sudo /sbin/modprobe"

#echo "   External Interface:  $EXTIF"
#echo "   Internal Interface:  $INTIF"

#======================================================================
#== No editing beyond this line is required for initial MASQ testing == 
#echo -en "   loading modules: "
#echo "  - Verifying that all kernel modules are ok"
logexec sudo $DEPMOD -a
#echo "----------------------------------------------------------------------"
echo -en "ip_tables, "
logexec $MODPROBE ip_tables
echo -en "nf_conntrack, " 
logexec $MODPROBE nf_conntrack
echo -en "nf_conntrack_ftp, " 
logexec $MODPROBE nf_conntrack_ftp
echo -en "nf_conntrack_irc, " 
logexec $MODPROBE nf_conntrack_irc
echo -en "iptable_nat, "
logexec $MODPROBE iptable_nat
echo -en "nf_nat_ftp, "
logexec $MODPROBE nf_nat_ftp
#echo "----------------------------------------------------------------------"
echo -e "   Done loading modules.\n"
#echo "   Enabling forwarding.."
$loglog
echo "1" | sudo tee /proc/sys/net/ipv4/ip_forward
#echo "   Enabling DynamicAddr.."
$loglog
echo "1" | sudo tee /proc/sys/net/ipv4/ip_dynaddr 
#echo "   Clearing any existing rules and setting default policy.."

logheredoc EOF
sudo iptables-restore <<-EOF
*nat
-A POSTROUTING -o "$EXTIF" -j MASQUERADE
COMMIT
*filter
:INPUT ACCEPT [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A FORWARD -i "$EXTIF" -o "$INTIF" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 
-A FORWARD -i "$INTIF" -o "$EXTIF" -j ACCEPT
-A FORWARD -j LOG
COMMIT
EOF

# logexec sudo route add -net $network gw $lxchostip dev $EXTIF

#echo -e "\nrc.firewall-iptables v$FWVER done.\n"
