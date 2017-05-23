#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Enhances creation of an empty LXC-2 container:
  sets ssh keys, apt-cacher client, upgrades and more. See the options below.


Usage:

$(basename $0) <container-name> [-r|--release <ubuntu release>] [-h|--hostname <fqdn>] 
                        [-a|--autostart] [-u|--username <username>] [--ip <static ip-address>] 
                        [-s|--grant-ssh-access-to <existing username on host>] 
                        [-p|--apt-proxy <address of the existing apt-proxy>] 
                        [--bridgeif <name of the bridge interface on host>] 
                        [--private-key-path <path to the private key>]
                        [--help] [--debug] [--log <output file>]

where

 -r|--release             - Ubuntu release to be installed, e.g. trusty. 
                            Defaults to currently used by host.
 -h|--hostname            - hostname, best if fqdn is given. Defaults to container name.
 -a|--autostart           - Flag if sets autostart for the container on host boot. Default: off.
 -u|--username            - Default username of the newly built container. Default: current user.
 --ip                     - If given, sets the static ip-address of the node. 
                            Requires sudo privileges on host.
 -s|--grant-ssh-access-to - username which will get automatic login via ssh to that container.
                            Defaults to `whoami`.
 -p|--apt-proxy           - Address of the existing apt-cacher.
 --bridgeif               - If set, name of the bridge interface the container will be connected to.
                            Defaults to the first available bridge interface used by LXD deamon.
 --private_key_path       - Path to the file with the ssh private key. If set, installs private
                            key on the user's account in the container.
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands


Example:

$(basename $0) mynode --release xenial --autostart --apt-proxy 192.168.10.2:3142 --private-key-path ~/.ssh/id_rsa
"

dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}
mypath=${0%/*}
mypath=`dir_resolve $mypath`
cd $mypath



name=$1
if [ -z "$name" ]; then
	echo "$usage"
	exit 0
fi

shift
autostart=NO
ssh=YES
release=`lsb_release -c | perl -pe 's/^Codename:\s*(.*)$/$1/'`
lxcip=auto
lxcfqdn=$name
private_key_path=''
common_debug=0
sshuser=`whoami`
lxcuser=`whoami`
hostuser=0


while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--debug)
	common_debug=1
	;;
	-h|--hostname)
	lxcfqdn="$1"
	shift
	;;
	-a|--autostart)
	autostart=YES
	;;
	-u|--username)
	lxcuser="$1"
	shift
	;;
	--ip)
	lxcip="$1"
	shift
	;;
	-r|--release)
	release="$1"
	shift
	;;
	-s|--grant-ssh-access-to)
	sshuser="$1"
	shift
	;;
	-p|--apt-proxy)
	aptproxy="$1"
	shift
	;;
	--log)
	log=$1
	shift
	;;
	--bridgeif)
	internalif=$1
	shift
	;;
	--private_key_path)
	private_key_path=$1
	shift
	;;
	--help)
        echo "$usage"
        exit 0
	;;
        -*)
        echo "Error: Unknown option: $1" >&2
        echo "$usage" >&2
        ;;
esac
done



if [ -n "$common_debug" ]; then
	if [ -z "$log" ]; then
		log=/dev/stdout
	fi
fi

if [ -n "$internalif" ]; then
	tmp=$(lxc network list | grep -F " $internalif " | head -n 1)
	regex="\|\s+([^ ]+)\s+\|\s+bridge\s+\|\sYES"
	if [[ $tmp =~ $regex ]]; then
		internalif=${BASH_REMATCH[1]}
	else
		errcho "The $internalif is not a bridge managed by lxc. You need to use lxc internal bridge."
	        echo "$usage" >&2
		exit -1
	fi
else
	tmp=$(lxc network list | grep -F "| bridge   | YES     | " | head -n 1)
	regex="\|\s+([^ ]+)\s+\|\s+bridge\s+\|\sYES"
	if [[ $tmp =~ $regex ]]; then
		internalif=${BASH_REMATCH[1]}
	else
		errcho "Cannot find working bridge. You need to configure lxd network."
		exit -1
	fi
fi

if [ "$sshuser" == "auto" ]; then
	sshuser=`whoami`
fi

if [ -n "$sshuser" ]; then
	sshhome=`getent passwd $sshuser | awk -F: '{ print $6 }'`
	if [ ! -f "$sshhome/.ssh/id_ed25519.pub" ]; then
		errcho "Warning: User on host does not have ssh keys generated. The script will generate them."
		logexec ssh-keygen -q -t ed25519 -N "" -a 100 -f "$sshhome/.ssh/id_ed25519"
		if [ $? -ne 0 ]; then
			exit 1
		fi
	fi
	sshkey=$sshhome/.ssh/id_ed25519.pub
fi


#if ! dpkg -s augeas-tools>/dev/null 2>/dev/null; then
#	logexec sudo apt-get --yes install augeas-tools
#fi

sudoprefix=""

hostlxcip=$(ifconfig $internalif  | grep 'inet addr:'| grep -v '127.0.0.1' | cut -d: -f2 | awk '{ print $1}')

if [ "$aptproxy" == "auto" ]; then
	if ! dpkg -s apt-cacher-ng>/dev/null 2>/dev/null; then
		logexec sudo apt-get --yes install apt-cacher-ng
	fi
	aptproxy="$hostlxcip:3142"
fi

#Ustawiamy fqdn i hostname...
#echo "Setting fqdn and hostname for the container and the host..."
echo "$lxcfqdn" | grep -Fq . 2>/dev/null
if [ $? -eq 0 ]; then
	lxcname=`echo $lxcfqdn | sed -En 's/^([^.]*)\.(.*)$/\1/p'` 
	hostsline="$lxcfqdn $lxcname" 
else
	lxcname=$lxcfqdn
	hostsline="$lxcname"
fi


#Jeśli kontenera nie ma, to go tworzymy
if $sudoprefix lxc info ${name}>/dev/null 2>/dev/null; then
	echo "container ${name} already installed!"
	while :
	do
		echo "(P)roceed or (A)bort?"
		read ans
		if [ "$ans" == "p" ] || [ "$ans" == "P" ]; then
			break
		else
			if [ "$ans" == "A" ] || [ "$ans" == "a" ]; then
				exit 1
			fi
		fi
	done
else
	logexec lxc init ubuntu:${release} ${name} 
#	logexec lxc stop ${name}
fi

if [ -n "${internalif}" ]; then
	logexec lxc network attach ${internalif} ${name} eth0
fi




#Ustawiamy wpis w hosts
if [ "$lxcip" != "auto" ]; then
	ifstate=$(lxc info ${name})
	pattern='^\s+eth0:\s+inet\s+([0-9./]*)'
	if [[ $ifstate =~ $pattern ]]; then
		actual_ip=${BASH_REMATCH[1]}
	fi

	staticleases=/etc/hosts
	if ! grep -q "^$lxcip $lxcname" $staticleases; then
		if grep -q "^$lxcip" $staticleases; then
			errcho "IP address $lxcip already reserved!"
			exit 1
		fi
		lxc config device set ${name} eth0 ipv4.address ${lxcip}

		if grep -q "^[\\s\\d\\.]+$lxcname" $staticleases; then
			#We need to replace the line rather than append
			if [ "$lxcname" == "$lxcfqdn" ]; then
				logexec sudo sed -i -e "/^[\\s\\d\\.]+$lxcname/$lxcip $lxcname/" $staticleases
			else
				logexec sudo sed -i -e "/^[\\s\\d\\.]+$lxcname/$lxcip $lxcname $lxcfqdn/" $staticleases
			fi
		else
			if [ "$lxcname" == "$lxcfqdn" ]; then
				$loglog
				echo "$lxcip $lxcname" | sudo tee -a $staticleases >/dev/null
			else
				$loglog
				echo "$lxcip $lxcname $lxcfqdn" | sudo tee -a $staticleases >/dev/null
			fi
		fi
		restartcontainer=1
	fi


#	tmpfile=$(mktemp)
#	$loglog
#	sudo grep -v ${lxcname} /var/lib/lxd/networks/${internalif}/dnsmasq.leases > ${tmpfile}
#	$loglog
#	cat ${tmpfile} | sudo tee /var/lib/lxd/networks/${internalif}/dnsmasq.leases 
#
#	if [ ! -d /etc/lxc ]; then
#		logexec sudo mkdir -p /etc/lxc
#	fi


#	staticleases=/etc/lxc/static_leases
#	staticleases=/var/lib/lxd/networks/${internalif}/dnsmasq.hosts
#	if [ ! -f $staticleases ]; then
#		logexec sudo touch $staticleases
#	fi
#
#	if ! grep -q "^$lxcname,$lxcip" $staticleases; then
#		if grep -q "$lxcip" $staticleases; then
#			errcho "IP address $lxcip already reserved!"
#			exit 1
#		fi
#		#lxc config device set ${name} eth0 ipv4.address ${lxcip}
#
#		if grep -q "^$lxcname,[\\s\\d\\.]+" $staticleases; then
#			#We need to replace the line rather than append
#			if [ "$lxcname" == "$lxcfqdn" ]; then
#				logexec sudo sed -i -e "/^$lxcname,[\\s\\d\\.]+/$lxcname,$lxcip/" $staticleases
#			fi
#		else
#			if [ "$lxcname" == "$lxcfqdn" ]; then
#				$loglog
#				echo "$lxcname,$lxcip" | sudo tee -a $staticleases >/dev/null
#			else
#				$loglog
#				echo "$lxcname,$lxcip" | sudo tee -a $staticleases >/dev/null
#			fi
#		fi
#		restartcontainer=1
#	fi
	logexec lxc config device set ${name} eth0 ipv4.address ${lxcip}

#	if [[ "$restartcontainer" == "1" ]]; then
#		if lxc config get ${name} volatile.last_state.power | grep -q -F "RUNNING"; then
#			logexec lxc stop ${name}
#		fi
#		logexec sudo service lxd restart
#	fi
#fi


#Zanim uruchomimy kontener, upewniamy się, że dostanie prawidłowy adres IP
#if [ "$lxcip" != "auto" ]; then
#	logexec sudo service lxd stop 
#
#	tmpfile=$(mktemp)
#	logexec sudo grep -v ${lxcname} /var/lib/lxd/networks/${internalif}/dnsmasq.leases > ${tmpfile}
#	cat ${tmpfile} | sudo tee /var/lib/lxd/networks/${internalif}/dnsmasq.leases 
#	logexec sudo service lxd start 
fi



#Upewniamy się, że kontener jest uruchomiony
if lxc config get ${name} volatile.last_state.power | grep -q -F "STOPPED" 2>/dev/null  ; then
	echo "Starting the container..."
	logexec $sudoprefix lxc start $name
fi

if [ -z $(lxc config get ${name} volatile.last_state.power) ] ; then
	echo "Starting the container..."
	logexec $sudoprefix lxc start $name
fi


	
if lxc config get ${name} volatile.last_state.power | grep -q -F "STOPPED"; then
	errcho "Failed to start lxc container $name!"
	exit 1
fi

#actual_ip=$(lxc info $name | grep -E "eth0:\sinet\s+" | grep -E -o "[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}")
echo "Waiting for the container to obtain ip address..."

while [ -z "${actual_ip}" ]
do
actual_ip=$(lxc exec $name -- ifconfig eth0 | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')
sleep 1
done
echo "Got IP address ${actual_ip}"


#Upewniamy się, że kontener ma prawidłwy hostname...
if ! lxc exec ${name} -- grep -q ${lxcname} /etc/hostname ; then
	$loglog 
	echo ${lxcname} | lxc exec $name -- tee /etc/hostname >/dev/null
fi

#...i prawidłowy wpis w /etc/hosts...
if lxc exec $name -- grep -q "^127\.0\.1\.1" /etc/hosts; then
	logexec lxc exec $name -- sed -i "s/^\(127\.0\.1\.1\s*\).*/\1$hostsline/" /etc/hosts
else
	$loglog 
	echo "127.0.1.1	$hostsline" | lxc exec $name -- tee -a /etc/hosts >/dev/null
fi


#Jeśli zachodzi potrzeba, to upewniamy się, że kontener dostał prawidłowy adres IP
if [ "$lxcip" != "auto" ]; then
	if [ "$actual_ip" != "$lxcip" ]; then
		errcho "Wrong IP address of $name. Restarting dnsmasq and emptying its cache, then restarting the container..."
		logexec lxc stop $name

		logexec sudo service lxd stop 

		tmpfile=$(mktemp)
#		$loglog
		logexec sudo grep -v ${lxcname} /var/lib/lxd/networks/${internalif}/dnsmasq.leases > ${tmpfile}
#		$loglog
		cat ${tmpfile} | sudo tee /var/lib/lxd/networks/${internalif}/dnsmasq.leases 

		logexec sudo service lxd start 

		logexec lxc start $name
		sleep 5
		actual_ip=$(lxc info $name | grep -E "eth0:\sinet\s+" | grep -E -o "[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}")
		if [ "$actual_ip" != "$lxcip" ]; then
			errcho "Unable to set the IP address. It should be $lxcip, but the actual value is $actual_ip!"
			exit 5
		fi
	fi
fi



#Ustawiamy autostart...
#echo "Setting the autostart option..."
if [ "$autostart" == "YES" ]; then
	logexec lxc config set $name boot.autostart 1
else
	if [ "$autostart" == "NO" ]; then
		logexec lxc config set $name boot.autostart 0
	fi
fi


if [ -n "$aptproxy" ]; then
	$loglog
	echo "Acquire::http { Proxy \"http://$aptproxy\"; };" | lxc exec $name -- tee /etc/apt/apt.conf.d/90apt-cacher-ng >/dev/null
fi

# Creating user $lxcuser in the container
if [ "$lxcuser" != "ubuntu" ]; then
	logexec lxc exec $name -- adduser --quiet $lxcuser --disabled-password --gecos ""
	logexec lxc exec $name -- su -l $lxcuser -c "mkdir ~/.ssh"
	logexec lxc exec $name -- chmod 700 /home/$lxcuser/.ssh
fi

logexec lxc exec ${name} -- usermod -aG sudo  $lxcuser

if [ -f "$sshkey" ]; then
	mypubkey=$(cat $sshhome/.ssh/id_ed25519.pub)
	if ! lxc exec $name -- grep -q -F "$mypubkey" $sshhome/.ssh/authorized_keys 2>/dev/null; then
		$loglog
		cat $sshhome/.ssh/id_ed25519.pub | lxc exec $name -- su -l $lxcuser -c "tee --append ~/.ssh/authorized_keys" >/dev/null
	fi
fi


#echo "Adding the container to the hosts known_hosts file..."
if [ ! -d $sshhome/.ssh ]; then
	logexec mkdir $sshhome/.ssh
fi

if [ -f "$sshhome/.ssh/known_hosts" ]; then
	logexec ssh-keygen -f "$sshhome/.ssh/known_hosts" -R $name 2>/dev/null >/dev/null
	logexec ssh-keygen -f "$sshhome/.ssh/known_hosts" -R $lxcfqdn 2>/dev/null >/dev/null
	if [ -n "$actual_ip" ]; then
		logexec ssh-keygen -f "$sshhome/.ssh/known_hosts" -R $actual_ip 2>/dev/null >/dev/null
	fi
fi

$loglog 
ssh-keyscan -H $name >> $sshhome/.ssh/known_hosts 2>/dev/null
$loglog 
ssh-keyscan -H $lxcfqdn >> $sshhome/.ssh/known_hosts 2>/dev/null
if [ -n "$actual_ip" ]; then
	$loglog 
	ssh-keyscan -H $actual_ip >> $sshhome/.ssh/known_hosts 2>/dev/null
fi

#Echo Adding non-password sudo entry for our user
$loglog
echo "$lxcuser ALL=(ALL) NOPASSWD:ALL" | lxc exec $name -- tee /etc/sudoers.d/${lxcuser}_nopasswd 

#Updating, upgrading, installing simple stuff

logexec lxc exec $name -- apt update
logexec lxc exec $name -- apt --yes upgrade
logexec lxc exec $name -- apt install --yes liquidprompt byobu
logexec lxc exec $name -- liquidprompt_activate
logexec lxc exec $name -- su -l ${lxcuser} -c liquidprompt_activate
logexec lxc exec $name -- locale-gen en_US.UTF-8
logexec lxc exec $name -- locale-gen pl_PL.UTF-8

if [ -z $private_key_path ]; then
	logexec lxc exec $name -- su -l ${lxcuser} -c "ssh-keygen -t ed25519 -a 100 -f ~/.ssh/id_ed25519 -P ''"
else
	logexec lxc file push ${private_key_path} ${name}${sshhome}/.ssh/ >/dev/null
	logexec lxc exec ${name} -- chown ${lxcuser}:${lxcuser} ${sshhome}/.ssh/$(basename $private_key_path)
	logexec lxc exec ${name} -- chmod 0400 ${sshhome}/.ssh/$(basename $private_key_path)
	logexec echo "Installed the following ssh key:"
	logexec lxc exec ${name} -- ssh-keygen -lvf ${sshhome}/.ssh/$(basename $private_key_path)
fi

