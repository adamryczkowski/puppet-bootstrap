#!/bin/bash
cd `dirname $0`

. ./common.sh

#Configures lxc-net on the host. The script is compatible with Ubuntu 14.04 and lxc1.

#syntax:
#configure-lxc [-i|--internalif] <internal if name, e.g. lxcbr0> [-h|--hostip] <host ip, e.g. 10.0.14.1> [-n|--network <network domain, e.g. 10.0.14.0/24>] [--dhcprange] <dhcp range, e.g. '10.0.14.3,10.0.14.254' [--usermode]
# -i|--internalif - internal if name, e.g. lxcbr0
# -h|--hostip - host ip, e.g. 10.0.14.1
# -n|--network network domain e.g. 10.0.14.0/24
# --dhcprange - dhcp range, e.g. '10.0.14.3,10.0.14.254'
# --usermode-user - if provided, usermode containers will be setup for this user and the user will get all necessary privileges granted
internalif=auto
lxchostip=auto
lxcnetwork=auto
lxcnetmask=auto
lxcdhcprange=auto
usermode=0
needsrestart=0
user=`whoami`

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

if ! dpkg -s lxc >/dev/null 2>/dev/null; then
	logexec sudo apt-get --yes install lxc
fi

#Installing better version of upstart scripts
if [ ! -f /etc/init/lxc-net.conf.bak ]; then
	logexec sudo service lxc-net stop || true
	if [ -f /etc/init/lxc-net.conf ]; then
		logexec sudo mv /etc/init/lxc-net.conf /etc/init/lxc-net.conf.bak
	fi
	logexec sudo cp upstart-scripts/lxc-net.conf /etc/init/lxc-net.conf
	if [ ! -f /etc/init/lxc-dnsmasq.conf ]; then
		logexec sudo cp upstart-scripts/lxc-dnsmasq.conf /etc/init/lxc-dnsmasq.conf
	fi
	logexec sudo touch /etc/lxc/dnsmasq.conf
	logexec sudo service lxc-net start
	logexec sudo service lxc-dnsmasq start ||true
fi

if ! dpkg -s augeas-tools >/dev/null 2>/dev/null; then
	logexec sudo apt-get --yes install augeas-tools
fi

restart=no

if [ "$internalif" != "auto" ]; then
	logexec sudo augtool -L -A --transform "Shellvars incl /etc/default/lxc-net" set "/files/etc/default/lxc-net/LXC_BRIDGE" $internalif
	restart=yes
else
	internalif=`augtool -L -A --transform "Shellvars incl /etc/default/lxc-net" get "/files/etc/default/lxc-net/LXC_BRIDGE" | sed -En 's/\/.* = \"?([^\"]*)\"?$/\1/p'`
fi


if grep '#LXC_DHCP_CONFILE' /etc/default/lxc-net >/dev/null; then
	$loglog
	sudo sed -i -e "/\#LXC_DHCP_CONFILE/ s/\#//" /etc/default/lxc-net
fi
if grep '#LXC_DOMAIN' /etc/default/lxc-net >/dev/null; then
	$loglog
	sudo sed -i -e "/\#LXC_DOMAIN/ s/\#//" /etc/default/lxc-net
fi

if [ "$usermode" -eq 1 ]; then
	#Ekstra rzeczy, jakie trzeba ustawić, aby to były kontenery user-space

	sshhome=`getent passwd $user | awk -F: '{ print $6 }'`
	if [ -z "$sshhome" ]; then
		logexec sudo adduser --disabled-password --add_extra_groups --quiet --gecos "" ${user}
		sshhome=`getent passwd $user | awk -F: '{ print $6 }'`
	fi

	if [ -d "/home/.ecryptfs/$user" ]; then
		if [ ! -L $sshhome/.local/share/lxc ]; then
			logexec sudo rm -rf $sshhome/.config/lxc $sshhome/.local/share/lxc
			if [ ! -d /opt/lxc ]; then
				logexec sudo mkdir /opt/lxc
				logexec sudo chown -R $user /opt/lxc
				logexec mkdir /opt/lxc/config /opt/lxc/store
			fi
			logexec ln -s /opt/lxc/store $sshhome/.local/share/lxc
			logexec ln -s /opt/lxc/config $sshhome/.config/lxc
		fi
	fi

	if ! groups $user | grep &>/dev/null '\bsudo\b'; then
		logexec sudo adduser $user sudo
	fi

	if [ "$user" != "`whoami`" ]; then
		sudoprefix="sudo -u $user"
	fi

	if grep -q "$user:100000:165536" "/etc/subuid">/dev/null; then
		echo "subuids already defined for the user"
	else
		logexec sudo usermod --add-subuids 100000-165536 $user
	fi
	if grep -q "$user:100000:165536" "/etc/subgid">/dev/null; then
		echo "subuids already defined for the user"
	else
		logexec sudo usermod --add-subgids 100000-165536 $user
	fi
	logexec sudo chmod +x $sshhome
	if [ ! -d "$sshhome/.local/share/lxc" ]; then
		logexec $sudoprefix mkdir -p "$sshhome/.local/share/lxc"
	fi
	if [ ! -d "$sshhome/.config/lxc" ]; then
		logexec $sudoprefix mkdir -p "$sshhome/.config/lxc"
	fi
	logheredoc EOT
	$sudoprefix tee $sshhome/.config/lxc/default.conf >/dev/null <<EOT
lxc.include = /etc/lxc/default.conf
lxc.id_map = u 0 100000 65536
lxc.id_map = g 0 100000 65536
EOT
	if ! grep "$user veth $internalif 10" /etc/lxc/lxc-usernet >/dev/null; then
		$loglog
		echo "$user veth $internalif 10" | sudo tee -a /etc/lxc/lxc-usernet >/dev/null
	fi

	if [ ! -d $sshhome/.cache/lxc/download ]; then
		logexec $sudoprefix mkdir -p $sshhome/.cache/lxc
	fi
	if [ -d lxc-cache ]; then
		logexec $sudoprefix rsync -avr lxc-cache/* $sshhome/.cache/lxc
	fi
	logexec sudo chmod -R +x $sshhome/.local
fi

if [ "$lxchostip" != "auto" ]; then
	logexec sudo augtool -L -A --transform "Shellvars incl /etc/default/lxc-net" set "/files/etc/default/lxc-net/LXC_ADDR" $lxchostip
	restart=yes
fi

if [ "$lxcnetwork" != "auto" ]; then
	logexec sudo augtool -L -A --transform "Shellvars incl /etc/default/lxc-net" set "/files/etc/default/lxc-net/LXC_NETWORK" $lxcnetwork
	restart=yes
fi


if [ "$lxcnetmask" != "auto" ]; then
	logexec sudo augtool -L -A --transform "Shellvars incl /etc/default/lxc-net" set "/files/etc/default/lxc-net/LXC_NETMASK" $lxcnetmask
	restart=yes
fi

if [ "$lxcdhcprange" != "auto" ]; then
	logexec sudo augtool -L -A --transform "Shellvars incl /etc/default/lxc-net" set "/files/etc/default/lxc-net/LXC_DHCP_RANGE" $lxcdhcprange
	restart=yes
fi


if [ "$restart" == "yes" ]; then
	logexec sudo service lxc-net stop
	logexec sudo rm /var/lib/misc/dnsmasq.$internalif.leases
	logexec sudo service lxc-net start
fi

if [ "$needsrestart" -eq 1 ]; then
	echo "You need to log off the current session!"
	exit -1
fi
