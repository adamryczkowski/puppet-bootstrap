#!/bin/bash
cd `dirname $0`
. ./common.sh

#Ten skrypt tworzy lxc node o zadanej nazwie i parametrach. Ma możliwość dodania dostępu przez ssh, ustawienia autostartu, etc.

#syntax:
#make-lxc-node <container-name> [-r|--release <ubuntu release>] [-h|--hostname <fqdn>] [-a|--autostart] [-u|--username <username>] [--ip <static ip-address>] [-s|--grant-ssh-access-to <existing username on host>] [-p|--apt-proxy <address of the existing apt-proxy>] [--usermode]
#Not working: [-p|--apt-proxy <address of apt-proxy used by the creation process AND the node]
# -r|--release - ubuntu release, e.g. trusty, defaults to current
# -h|--hostname - hostname, best if fqdn is given
# -a|--autostart - if set, the container will autostart
# -u|--username - default username of the container. Of course other users can be done, since this container will be a working Ubuntu distro.
# --ip  - If given, sets the static ip-address of the node
# -s|--grant-ssh-access-to - username which will get automatic login via ssh to that container; defaults to `whoami`
# -p|--apt-proxy - address of the existing apt-proxy
# --usermode - if set, the resulting container will be a user mode container.

dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}
mypath=${0%/*}
mypath=`dir_resolve $mypath`
cd $mypath

name=$1
shift
autostart=NO
ssh=YES
release=`lsb_release -c | perl -pe 's/^Codename:\s*(.*)$/$1/'`
lxcip=auto
lxcfqdn=$name
debug=0
sshuser=`whoami`
lxcuser=`whoami`
hostuser=0
usermode=0
internalif=`augtool -L -A --transform "Shellvars incl /etc/default/lxc-net" get "/files/etc/default/lxc-net/LXC_BRIDGE" | sed -En 's/\/.* = \"?([^\"]*)\"?$/\1/p'`

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--debug)
	debug=1
	;;
	--usermode)
	usermode=1
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
	*)
	errcho "Unkown parameter '$key'. Aborting."
	exit 1
	;;
esac
done

if [ "$sshuser" == "auto" ]; then
	sshuser=`whoami`
fi

if [ -n "$sshuser" ]; then
	sshhome=`getent passwd $sshuser | awk -F: '{ print $6 }'`
	if [ ! -f "$sshhome/.ssh/id_rsa.pub" ]; then
		errcho "Warning: User on host does not have ssh keys generated. The script will generate them."
		logexec ssh-keygen -q -t rsa -N "" -f "$sshhome/.ssh/id_rsa"
		if [ $? -ne 0 ]; then
			exit 1
		fi
	fi
	sshkey=$sshhome/.ssh/id_rsa.pub
fi


if ! dpkg -s augeas-tools>/dev/null 2>/dev/null; then
	logexec sudo apt-get --yes install augeas-tools
fi

if [ "$usermode" -eq 0 ]; then
	sudoprefix="sudo"
else
	sudoprefix=""
fi

if [ "$aptproxy" == "auto" ]; then
	if ! dpkg -s apt-cacher-ng>/dev/null 2>/dev/null; then
		logexec sudo apt-get --yes install apt-cacher-ng
	fi
	hostlxcip=`sudo augtool -L -A --transform "Shellvars incl /etc/default/lxc-net" get "/files/etc/default/lxc-net/LXC_ADDR" | sed -En 's/\/.* = (.*)/\1/p'`
	aptproxy="$hostlxcip:3142"
fi


#Jeśli kontenera nie ma, to go tworzymy
if $sudoprefix lxc-info -n ${name}>/dev/null 2>/dev/null; then
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
	if [ "$usermode" -eq 1 ]; then
		logexec lxc-create -t download -n ${name} -- -d ubuntu -r ${release} -a amd64
		lxcpath=$sshhome/.local/share/lxc/$name
	else
		opts="-r ${release} -u ${lxcuser}"
		if [ -n "$aptproxy" ]; then
			eval $(apt-config shell MIRROR_PREFIX Acquire::http::Proxy)
			#Gets rid of trailing slash
			if [[ "$MIRROR_PREFIX" =~ (.*)/$ ]]; then
				MIRROR_PREFIX=${BASH_REMATCH[1]}
			fi
			opts="$opts --mirror $MIRROR_PREFIX/archive.ubuntu.com/ubuntu"
		fi
		if [ -f "$sshkey" ]; then
			opts="$opts --auth-key $sshkey"
		fi
		logexec sudo lxc-create -n ${name} -t ubuntu -- $opts
		lxcpath=/var/lib/lxc/$name
	fi
fi

#Jeśli ma mieć stałe IP, to wpisujemy odpowiedni wpis do dnsmasq i restartujemy service
if [ "$lxcip" != "auto" ]; then
	#Upewniamy się, że rzeczywiście jest sens modyfikować /etc/lxc/dnsmasq.conf...
	logexec sudo sed -i -e "/\#\s*LXC_DHCP_CONFILE=\/etc\/lxc\/dnsmasq.conf/ s/\#\s//" /etc/default/lxc-net
	#Dokonujemy teraz zmian...
#	echo "Restarting dnsmasq..."
	logexec sudo service lxc-dnsmasq stop || true >/dev/null
#	if [ -d /sys/class/net/$internalif ]; then
#		sudo brctl delbr lxcbr0 >/dev/null
#	fi
#	if [ -f /run/lxc/dnsmasq.pid ]; then
#		sudo kill -HUP `cat /run/lxc/dnsmasq.pid`
#	fi
	
	if [ -f /var/lib/misc/dnsmasq.$internalif.leases ]; then
		logexec sudo rm /var/lib/misc/dnsmasq.$internalif.leases 2>/dev/null
	fi
	if ! grep -q "dhcp-host=$name,$lxcip" /etc/lxc/dnsmasq.conf; then
		if grep -q "dhcp-host=[^,]+,$lxcip" /etc/lxc/dnsmasq.conf; then
			errcho "IP address $lxcip already reserved!"
			exit 1
		fi
		if grep -q "dhcp-host=$name,.*" /etc/lxc/dnsmasq.conf; then
			#We need to replace the line rather than append
			$loglog
			sudo sed -i -e "/dhcp-host=$name,.*/ s/\(dhcp-host=$name,\).*/\1$lxcip/g" /etc/lxc/dnsmasq.conf
		else
			$loglog
			echo "dhcp-host=$name,$lxcip" | sudo tee -a /etc/lxc/dnsmasq.conf >/dev/null
		fi
	fi
	logexec sudo service lxc-dnsmasq start
fi

#Ustawiamy fqdn i hostname...
#echo "Setting fqdn and hostname for the container and the host..."
echo $lxcfqdn | grep -Fq . >/dev/null
if [ $? -eq 0 ]; then
	lxcname=`echo $lxcfqdn | sed -En 's/^([^.]*)\.(.*)$/\1/p'` 
	hostsline="$lxcfqdn $lxcname" 
else
	lxcname=$lxcfqdn
	hostsline="$lxcname"
fi

if [ "$ip" != "auto" ]; then
	if ! grep -q $lxcfqdn /etc/hosts 2>/dev/null >/dev/null; then
		if [ "$lxcname" == "$lxcfqdn" ]; then
			echo "$lxcip $lxcname" | sudo tee -a /etc/hosts >/dev/null
		else
			echo "$lxcip $lxcname $lxcfqdn" | sudo tee -a /etc/hosts >/dev/null
		fi
	fi
fi


#Upewniamy się, że kontener ma prawidłwy hostname...
if ! $sudoprefix grep -q $lxcname "$lxcpath/rootfs/etc/hostname" 2>/dev/null >/dev/null; then
	$loglog 
	echo $lxcname | $sudoprefix tee $lxcpath/rootfs/etc/hostname >/dev/null
fi

#...i prawidłowy wpis w /etc/hosts...

if sudo grep "^127\.0\.1\.1" $lxcpath/rootfs/etc/hosts 2>/dev/null >/dev/null; then
	logexec sudo sed -i "s/^\(127\.0\.1\.1\s*\).*/\1$hostsline/" $lxcpath/rootfs/etc/hosts
else
	$loglog 
	echo "127.0.1.1	$hostsline" | $sudoprefix tee -a $lxcpath/rootfs/etc/hosts >/dev/null
fi




#Upewniamy się, że kontener jest uruchomiony
if $sudoprefix lxc-info -n $name | grep "STOPPED" >/dev/null; then
#	echo "Starting the container..."
	logexec $sudoprefix lxc-start -d -n $name
	if [ $? -ne 0 ] && [ "$usermode" -eq "1" ]; then
		errcho "Należy zrestartować host - inaczej kreacja kontenera usermode nie uda się" >&2
		exit 1
	fi
	sleep 5
	
	if $sudoprefix lxc-info -n $name | grep "STOPPED" >/dev/null; then
		errcho "Failed to start lxc container $name!"
		exit 1
	fi
	if [ "$usermode" -eq 1 ]; then	
		logexec lxc-attach -n ${name} -- adduser --disabled-password --add_extra_groups --quiet --gecos "" ${lxcuser} 
	fi
fi
myip=`$sudoprefix lxc-info -n $name -i | grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"`

#Jeśli zachodzi potrzeba, to upewniamy się, że kontener dostał prawidłowy adres IP
if [ "$lxcip" != "auto" ]; then
	if [ "$myip" != "$lxcip" ]; then
		errcho "Wrong IP address of $name. Restarting dnsmasq and emptying its cache, then restarting the container..."
		logexec $sudoprefix lxc-stop -n $name
		logexec sudo service lxc-dnsmasq stop 
#		if [ -d /sys/class/net/$internalif ]; then
#			sudo brctl delbr lxcbr0 >/dev/null
#		fi
#		if [ -f /run/lxc/dnsmasq.pid ]; then
#			sudo kill -HUP `cat /run/lxc/dnsmasq.pid`
#		fi
#		sleep 2

		logexec sudo rm /var/lib/misc/dnsmasq.$internalif.leases
		logexec sudo service lxc-dnsmasq start 
		logexec $sudoprefix lxc-start -d -n $name 
		sleep 5
		myip=`$sudoprefix lxc-info -n $name -i | grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"`
		if [ "$myip" != "$lxcip" ]; then
			errcho "Unable to set the IP address. It should be $lxcip, but the actual value is $myip!"
			exit 5
		fi
	fi
fi


#Ustawiamy autostart...
#echo "Setting the autostart option..."
if [ "$autostart" == "YES" ]; then
	logexec $sudoprefix augtool -L -A --transform "PHP incl $lxcpath/config" set "/files/$lxcpath/config/.anon/lxc.start.auto" 1
else
	if [ "$autostart" == "NO" ]; then
		logexec $sudoprefix augtool -L -A --transform "PHP incl $lxcpath/config" set "/files/$lxcpath/config/.anon/lxc.start.auto" 0 
	fi
fi


#echo "Making sure, that for the next 15 minutes user can do sudo without the password (to be able to execute scripts with sudo)..."
if [ "$usermode" -eq "1" ]; then
	opts="--usermode"
else
	opts=""
fi
if [ -n "$log" ]; then
	opts="$opts --log $log"
fi
if [ "$debug" -eq "0" ]; then
	./force-sudo.sh $lxcname --lxcusername $lxcuser --lxcowner `whoami` $opts
else
	bash -x -- force-sudo.sh $lxcname --lxcusername $lxcuser --lxcowner `whoami` $opts
fi


function pingsudo
{

cat >/tmp/pingsudo.sh <<EOT
#!/bin/bash
sudo mkdir /var/lib/sudo/$1 2>/dev/null
while [[ 0 ]]
do
sleep 60
sudo touch /var/lib/sudo/$1/0
done
EOT

sudo cp /tmp/pingsudo.sh $lxcpath/rootfs/pingsudo.sh
sudo chmod +x $lxcpath/rootfs/pingsudo.sh
ssh $lxcuser@$lxcfqdn "/pingsudo.sh $puppetuser" &

pingsudopid=`jobs -p 1`
}

if [ -n "$aptproxy" ]; then
	$loglog
	echo "Acquire::http { Proxy \"http://$aptproxy\"; };" | sudo tee $lxcpath/rootfs/etc/apt/apt.conf.d/31apt-cacher-ng >/dev/null
fi

if [ "$usermode" -eq 1 ]; then
	logexec lxc-attach -n ${name} -- apt-get update
	logexec lxc-attach -n ${name} -- apt-get upgrade --yes
	logexec lxc-attach -n ${name} -- apt-get install --yes openssh-server language-pack-pl
	if [ -f "$sshkey" ]; then
		logexec sudo mkdir -p $lxcpath/rootfs/home/$lxcuser/.ssh
		logexec sudo cp $sshkey $lxcpath/rootfs/home/$lxcuser/.ssh/authorized_keys
		logexec sudo chown -R 101000:101000 $lxcpath/rootfs/home/$lxcuser/.ssh
		logexec lxc-attach -n ${name} -- chown -R $lxcuser:$lxcuser /home/$lxcuser/.ssh
		logexec lxc-attach -n ${name} -- adduser $lxcuser sudo >/dev/null
	fi
fi

#opts="--server $lxcfqdn --user-on-server $lxcuser --remote-host localhost --remote-user $sshuser --server-lxc-name $name"
#if [ "$debug" -eq "1" ]; then
#	bash -x ./ensure-ssh-access.sh $opts
#else
#	./ensure-ssh-access $opts
#fi

#echo "Adding the container to the hosts known_hosts file..."
if [ -f "$sshhome/.ssh/known_hosts" ]; then
	logexec ssh-keygen -f "$sshhome/.ssh/known_hosts" -R $name 
	logexec ssh-keygen -f "$sshhome/.ssh/known_hosts" -R $lxcfqdn 
	logexec ssh-keygen -f "$sshhome/.ssh/known_hosts" -R $myip 
fi

if [ ! -d $sshhome/.ssh ]; then
	logexec mkdir $sshhome/.ssh
fi
$loglog 
ssh-keyscan -H $name >> $sshhome/.ssh/known_hosts 2>/dev/null
$loglog 
ssh-keyscan -H $lxcfqdn >> $sshhome/.ssh/known_hosts 2>/dev/null
$loglog 
ssh-keyscan -H $myip >> $sshhome/.ssh/known_hosts 2>/dev/null


if [ "$usermode" -eq 0 ]; then
	pingsudo $lxcuser
	logexec ssh $lxcuser@$lxcfqdn "sudo apt-get update && sudo apt-get upgrade --yes"
	logexec ssh $lxcuser@$lxcfqdn "sudo apt-get install --yes language-pack-pl"
	kill $pingsudopid
fi

if [ -f "$lxcpath/rootfs/pingsudo.sh" ]; then
	logexec sudo rm $lxcpath/rootfs/pingsudo.sh
fi

