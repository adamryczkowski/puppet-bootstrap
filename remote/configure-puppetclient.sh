#!/bin/bash
cd `dirname $0`

#Ten skrypt konfiguruje puppet client na bierzącym komputerze.

#syntax:
#configure-puppetclient [-u|--puppetuser <username fact. Default: none>] [--puppetmaster <fqdn> ] [--myfqdn <fqdn of this node. Used as a name for puppet>]

. ./common.sh

puppetuser=
sshhome=`getent passwd $puppetuser | awk -F: '{ print $6 }'`
gitfolder=$sshhome/puppet

if ! sudo -n -- ls / >/dev/null 2>/dev/null; then
	echo "No sudo permissions!"
	exit 1
fi

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

if ! dpkg -s wget>/dev/null  2> /dev/null; then
	logexec sudo apt-get --yes install wget
fi


source /etc/lsb-release

if grep apt.puppetlabs /etc/apt/sources.list || grep apt.puppetlabs /etc/apt/sources.list.d/* >/dev/null 2>/dev/null; then
	echo "puppet repository already installed!"
else
	if [ -f "/tmp/puppetlabs-release-$DISTRIB_CODENAME.deb" ]; then
		echo "Puppet release deb already downloaded!"
	else
		$loglog
		wget -O "/tmp/puppetlabs-release-$DISTRIB_CODENAME.deb" http://apt.puppetlabs.com/puppetlabs-release-$DISTRIB_CODENAME.deb
	fi
	$loglog
	sudo dpkg -i "/tmp/puppetlabs-release-$DISTRIB_CODENAME.deb"
	logexec sudo apt-get update
	logexec rm /tmp/puppetlabs-release-$DISTRIB_CODENAME.deb
fi

if dpkg -s puppet >/dev/null 2>/dev/null; then
	sudo service puppet stop
	sudo rm -f /var/lib/puppet/ssl/certs/*
	sudo rm -f /var/lib/puppet/ssl/certificate_requests/*
	sudo rm -r /var/lib/puppet/ssl/crl.pem
	sudo service puppet start
else
	logexec sudo apt-get --yes install puppet
fi

if [ -n "$puppetmaster" ]; then
	if dpkg -s augeas-tools >/dev/null 2>/dev/null; then
		echo "augeas already installed!"
	else
		logexec sudo apt-get --yes install augeas-tools
	fi
	$loglog
	sudo augtool -L -A --transform "Puppet incl /etc/puppet/puppet.conf" set "/files/etc/puppet/puppet.conf/main/server" $puppetmaster
fi

mypuppetcert=`augtool -L -A --transform "Shellvars incl /etc/default/lxc-net" get "/files/etc/default/lxc-net/LXC_BRIDGE" | sed -En 's/\/.* = \"?([^\"]*)\"?$/\1/p'`
if [ "$mypuppetcert" != "$myfqdn" ]; then
	sudo augtool -L -A --transform "Puppet incl /etc/puppet/puppet.conf" set "/files/etc/puppet/puppet.conf/main/certname" $myfqdn
fi

sudo augtool -L -A --transform "Puppet incl /etc/puppet/puppet.conf" rm "/files/etc/puppet/puppet.conf/main/templatedir" $myfqdn


logexec sudo mkdir -p /etc/facter/facts.d

if [ -n "$puppetuser" ]; then
	logexec sudo tee /etc/facter/facts.d/userlocation.json <<EOT
{
  "user": "$puppetuser",
  "location": "LxcOnAm"
}
EOT
fi

$loglog
sudo service puppet restart || true

logexec sudo puppet agent --test

