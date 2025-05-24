#!/bin/bash
cd `dirname $0`

#Ten skrypt konfiguruje puppet client na bierzącym komputerze.

#syntax:
#configure-puppetclient [-u|--puppetuser <username fact. Default: none>] [--puppetmaster <fqdn> ] [--myfqdn <fqdn of this node. Used as a name for puppet>]

. ./common.sh

puppetuser=$USER

#if ! sudo -n -- ls / >/dev/null 2>/dev/null; then
#	echo "No sudo permissions!"
#	exit 1
#fi

while [[ $# > 0 ]]
do
	key="$1"
	shift

	case $key in
		-u|--puppetuser)
			puppetuser="$1"
			shift
			;;
		-s|--puppetmaster)
			puppetmaster=$1
			shift
			;;
		--log)
			log=$1
			shift
			;;
		--myfqdn)
			myfqdn=$1
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

if [ -z "$myfqdn" ]; then
	myfqdn=`hostname --fqdn`
else
	if [ "`cat /etc/hostname`" != "$myfqdn" ]; then
		$loglog
		echo "$myfqdn" | sudo tee /etc/hostname
	fi
fi

sshhome=`getent passwd $puppetuser | awk -F: '{ print $6 }'`
gitfolder=$sshhome/puppet


if ! dpkg -s wget>/dev/null  2> /dev/null; then
	logexec sudo apt-get --yes install wget
fi

source /etc/lsb-release

if [ ! -f /etc/apt/sources.list.d/puppetlabs-pc1.list ]; then
	if [ ! -f "/tmp/puppet-${DISTRIB_CODENAME}.deb" ]; then
		logexec curl https://apt.puppetlabs.com/puppetlabs-release-pc1-${DISTRIB_CODENAME}.deb -o /tmp/puppet-${DISTRIB_CODENAME}.deb
	fi
	logexec sudo dpkg -i "/tmp/puppet-${DISTRIB_CODENAME}.deb"
	logexec sudo apt-get update
	logexec rm /tmp/puppet-${DISTRIB_CODENAME}.deb
fi

if ! dpkg -s puppet-agent >/dev/null  2>/dev/null; then
	logexec sudo apt-get --yes install puppet-agent
fi

if ! grep "/opt/puppetlabs/puppet/bin" /etc/environment; then
	currentpath=$(bash -c "source /etc/environment; echo \$PATH")
	$loglog
	echo "PATH=/opt/puppetlabs/puppet/bin:${PATH}" | sudo tee /etc/environment
	export PATH=/opt/puppetlabs/puppet/bin:$PATH
fi

pattern="secure_path\\s*=.*/opt/puppetlabs/puppet/bin"
if ! sudo grep $pattern /etc/sudoers ; then
	pattern='^Defaults\s*secure_path\s*=\s*"(.*+)"\s*$'
	currentpath=$(sudo grep 'Defaults\s*secure_path\s*=\s*.*' /etc/sudoers)
	if [[ $currentpath =~ $pattern ]]; then
		currentpath=${BASH_REMATCH[1]}
		logexec sudo sed -i "/secure_path/c\Defaults secure_path=/opt/puppetlabs/puppet/bin:$currentpath" /etc/sudoers
	fi
fi


if dpkg -s puppet-agent >/dev/null 2>/dev/null; then
	sudo service puppet stop
	sudo rm -f /var/lib/puppet/ssl/certs/*
	sudo rm -f /var/lib/puppet/ssl/certificate_requests/*
	sudo rm -r /var/lib/puppet/ssl/crl.pem
	sudo service puppet start
else
	logexec sudo apt --yes install puppet-agent
fi

if [ -n "$puppetmaster" ]; then
	if dpkg -s augeas-tools >/dev/null 2>/dev/null; then
		echo "augeas already installed!"
	else
		logexec sudo apt-get --yes install augeas-tools
	fi
	logexec sudo augtool  --autosave --noautoload --transform "Puppet incl /etc/puppetlabs/puppet/puppet.conf" set "/files/etc/puppetlabs/puppet/puppet.conf/agent/server" ${puppetmaster}
fi

#sudo augtool -L -A --transform "Puppet incl /etc/puppet/puppet.conf" rm "/files/etc/puppet/puppet.conf/main/templatedir" $myfqdn


#logexec sudo mkdir -p /etc/facter/facts.d

#if [ -n "$puppetuser" ]; then
#	logexec sudo tee /etc/facter/facts.d/userlocation.json <<EOT
#{
#  "user": "$puppetuser",
#  "location": "LxcOnAm"
#}
#EOT
#fi

logexec sudo service puppet stop
logexec sudo rm -f /etc/puppetlabs/puppet/ssl/certs/*
logexec sudo rm -f /etc/puppetlabs/puppet/ssl/certificate_requests/*
logexec sudo rm -f /etc/puppetlabs/puppet/ssl/certificate_requests/*
logexec sudo rm -f /etc/puppetlabs/puppet/ssl/certificate_requests/*
logexec
logexec sudo service puppet start

logexec sudo /opt/puppetlabs/puppet/bin/puppet agent --test
