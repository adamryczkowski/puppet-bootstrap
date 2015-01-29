#!/bin/bash
cd `dirname $0`

#Ten skrypt konfiguruje puppetmaster na bierzącym komputerze.

#syntax:
#configure-puppetmaster [-d|--domainname <domain name. Needed, if cannot be determined.>] [-u|--puppetuser <name of the user to work with puppet's git repo>] [-g|--git-folder <local folder with working copy of git repository>] [-s|--git-source <URI to pre-existing git repository] [--r10k-gems-path <path to the gem cache>]
#-d|--domainname - domain name. Needed, if cannot be determined.
#-u|--puppetuser - name of the user to work with puppet's git repo
#-g|--git-folder - folder with working copy of git repository, defaults to ~/puppet
#--r10k-gems-path - <path to the gem cache. Useful if no or little internet is available>]

. ./common.sh

export fqdn=`hostname --fqdn`

if echo $fqdn | grep -Fq .; then
	domainname=`echo $fqdn | sed -En 's/^([^.]*)\.(.*)$/\2/p'`
else
	domainname=NONE
fi

puppetuser=`whoami`
sshhome=`getent passwd $puppetuser | awk -F: '{ print $6 }'`
gitfolder=$sshhome/puppet


if ! sudo -n 'ls>/dev/null' 2>/dev/null; then
	echo "No sudo permissions!"
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

chmod +x /tmp/pingsudo.sh
bash -x -- "/tmp/pingsudo.sh" &
pingsudopid=`jobs -p 1`
return `jobs -p 1`
}

# pingsudo $puppetuser

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	-d|--domainname)
	domainname="$1"
	shift
	;;
	--debug)
	debug=1
	;;
	-u|--puppetuser)
	puppetuser="$1"
	shift
	;;
	-g|--git-folder)
	gitfolder="$1"
	shift
	;;
	--r10k-gems-cache)
	gemcache="$1"
	shift
	;;
	--log)
	log="$1"
	shift
	;;
	*)
	echo "Unkown parameter '$key'. Aborting."
	exit 1
	;;
esac
done

if [ "$domainname" == "NONE" ]; then
	errcho "Cannot determine fully qualified domain name (fqdn) for host. Specify it in --domainname parameter or with any other method, so 'hostname --fqdn' can return it."
	exit 1
fi

if ! sudo -n 'ls'; then
	errcho "No sudo permissions!"
	exit 0
fi



if ! dpkg -s wget >/dev/null  2>/dev/null; then
	logexec sudo apt-get --yes install wget
fi

if ! dpkg -s augeas-tools>/dev/null 2>/dev/null; then
	logexec sudo apt-get --yes install augeas-tools
fi

source /etc/lsb-release

if ! grep apt.puppetlabs /etc/apt/sources.list  || grep apt.puppetlabs /etc/apt/sources.list.d/* >/dev/null 2>/dev/null; then
	if [ ! -f "/tmp/puppetlabs-release-$DISTRIB_CODENAME.deb" ]; then
		logexec wget -O "/tmp/puppetlabs-release-$DISTRIB_CODENAME.deb" http://apt.puppetlabs.com/puppetlabs-release-$DISTRIB_CODENAME.deb
	fi
	logexec sudo dpkg -i "/tmp/puppetlabs-release-$DISTRIB_CODENAME.deb"
	logexec sudo apt-get update
	logexec rm /tmp/puppetlabs-release-$DISTRIB_CODENAME.deb
fi

if ! dpkg -s puppetmaster >/dev/null  2>/dev/null; then
    logexec sudo apt-get --yes install puppetmaster puppetdb-terminus
fi

logexec sudo adduser $puppetuser puppet >/dev/null



if [ ! -d /etc/puppet/environments ]; then
	logexec sudo mkdir /etc/puppet/environments
	logexec sudo chgrp puppet /etc/puppet/environments
	logexec sudo chmod 2775 /etc/puppet/environments
fi

logexec sudo augtool -L -A --transform "Puppet incl /etc/puppet/puppet.conf" set "/files/etc/puppet/puppet.conf/main/environment" production
logexec sudo augtool -L -A --transform "Puppet incl /etc/puppet/puppet.conf" set "/files/etc/puppet/puppet.conf/main/confdir" /etc/puppet
logexec sudo augtool -L -A --transform "Puppet incl /etc/puppet/puppet.conf" set "/files/etc/puppet/puppet.conf/main/server" $fqdn 
logexec sudo augtool -L -A --transform "Puppet incl /etc/puppet/puppet.conf" rm "/files/etc/puppet/puppet.conf/main/templatedir" 

logexec sudo augtool -L -A --transform "Puppet incl /etc/puppet/puppet.conf" set "/files/etc/puppet/puppet.conf/agent/environment" production 
logexec sudo augtool -L -A --transform "Puppet incl /etc/puppet/puppet.conf" set "/files/etc/puppet/puppet.conf/agent/report" true 
logexec sudo augtool -L -A --transform "Puppet incl /etc/puppet/puppet.conf" set "/files/etc/puppet/puppet.conf/agent/show_diff" true 

logexec sudo augtool -L -A --transform "Puppet incl /etc/puppet/puppet.conf" set "/files/etc/puppet/puppet.conf/master/environment" production 
logexec sudo augtool -L -A --transform "Puppet incl /etc/puppet/puppet.conf" set "/files/etc/puppet/puppet.conf/master/environmentpath" '$confdir/environments' 


logheredoc EOT
sudo tee /etc/puppet/hiera.yaml >/dev/null <<'EOT'
---
:hierarchy:
  - "nodes/%{::fqdn}"
  - "manufacturers/%{::manufacturer}"
  - "virtual/%{::virtual}"
  - common
:backends:
  - yaml
:yaml:
  :datadir: "/etc/puppet/environments/%{::environment}/hieradata"
EOT

logexec sudo ln -sf /etc/puppet/hiera.yaml /etc/hiera.yaml

logexec sudo service puppetmaster restart

exitcode=0
$loglog
sudo puppet agent --test || exitcode=$?

if [ "$exitcode" -ne "0" ]; then
	logmsg "Puppet agent generated error $exitcode; aborting"
	exit $exitcode
fi

if ! gem list --local | grep r10k >/dev/null; then
	if [ -n "$gemcache" ]; then
		logexec sudo gem install --force --local $gemcache/*.gem
		if ! gem list --local | grep r10k >/dev/null; then
			echo "Offline instalation of gems from folder $gemcache failed."
			exit 1
		fi
	else
		logexec sudo gem install r10k
	fi
fi

logexec sudo mkdir /var/cache/r10k
logexec sudo chgrp puppet /var/cache/r10k
logexec sudo chmod 2775 /var/cache/r10k

logheredoc EOT
sudo tee /etc/r10k.yaml <<'EOT' >/dev/null
# location for cached repos
:cachedir: '/var/cache/r10k'

# git repositories containing environments
:sources:
  :base:
    remote: '/srv/puppet.git'
    basedir: '/etc/puppet/environments'

# purge non-existing environments found here
:purgedirs:
  - '/etc/puppet/environments'
EOT

if ! dpkg -s git >/dev/null  2>/dev/null; then
	logexec sudo apt-get --yes install git
fi

logexec git config --global user.email "$puppetuser@$fqdn"
logexec git config --global user.name "Puppet Master"

if [ ! -d /srv/puppet.git ]; then
	logexec sudo git init --bare --shared=group /srv/puppet.git
	logexec sudo chgrp -R puppet /srv/puppet.git
	logexec cd /srv/puppet.git
	logexec sudo -u $puppetuser git symbolic-ref HEAD refs/heads/production	
fi

##Trick poniższy spowoduje, że reszta tego skryptu zostania wykonana jako NOWY użytkownik $puppetuser - tj. ten, który jest członkiem grupy puppet (i ma prawa zapisu do /srv/puppet.git)
#tail -n +$[LINENO+2] "$SCRIPT_PATH" | exec sudo bash -x
#exit $?

if [ ! -f /srv/puppet.git/hooks/post-receive ]; then
	logheredoc EOT
	sudo -u $puppetuser tee /srv/puppet.git/hooks/post-receive <<'EOT' >/dev/null
#!/bin/bash

umask 0002

while read oldrev newrev ref
do
    branch=$(echo $ref | cut -d/ -f3)
    echo
    echo "--> Deploying ${branch}..."
    echo
    find /etc/puppet/environments/$branch/modules -type d -exec chmod 2775 {} \; 2> /dev/null
    find /etc/puppet/environments/$branch/modules -type f -exec chmod 664 {} \; 2> /dev/null
    r10k deploy environment $branch -p
    find /etc/puppet/environments/$branch/modules -type d -exec chmod 2775 {} \; 2> /dev/null
    find /etc/puppet/environments/$branch/modules -type f -exec chmod 664 {} \; 2> /dev/null
    # sometimes r10k gets permissions wrong too
done
EOT
fi

if [ ! -f /usr/local/bin/deploy ]; then
	logheredoc EOT
	sudo tee /usr/local/bin/deploy <<'EOT' >/dev/null
!/bin/sh

umask 0002

r10k deploy environment $1 -p

find /etc/puppet/environments -mindepth 1 -type d -exec chmod 2775 {} \;
find /etc/puppet/environments -type f -exec chmod 0664 {} \;
EOT
fi

logexec sudo -u $puppetuser chmod 0775 /srv/puppet.git/hooks/post-receive


if [ ! -d $gitfolder/.git ]; then
	logexec mkdir -p `dirname $gitfolder` 
	logexec git clone /srv/puppet.git $gitfolder
fi
logexec cd $gitfolder

logexec mkdir -p hieradata/nodes manifests site 

loglog 
echo "modulepath = modules:site" >$gitfolder/environment.conf

logheredoc EOT
tee $gitfolder/Puppetfile <<'EOT' >/dev/null
# Puppet Forge
mod 'puppetlabs/ntp'
mod 'puppetlabs/puppetdb'
mod 'puppetlabs/stdlib'
mod 'puppetlabs/concat'
mod 'puppetlabs/inifile'
mod 'puppetlabs/postgresql'
mod 'puppetlabs/firewall'

# A module from your own git server
#mod 'custom',
#  :git => 'git://git.mydomain.com/custom.git',
#  :ref => '1.0'
EOT

logheredoc EOT
tee $gitfolder/hieradata/common.yaml <<'EOT' >/dev/null
---
classes:
  - ntp

ntp::servers:
  - 0.pool.ntp.org
  - 1.pool.ntp.org
  - 2.pool.ntp.org
  - 3.pool.ntp.org
EOT

logheredoc EOT
tee $gitfolder/hieradata/nodes/$(hostname -f).yaml <<'EOT' >/dev/null
---
classes:
  - puppetdb
  - puppetdb::master::config
puppetdb::database: embedded
EOT

logheredoc EOT
tee $gitfolder/manifests/site.pp <<'EOT' >/dev/null
hiera_include('classes')
EOT

logexec touch $gitfolder/site/.keep
logexec git checkout -b production
logexec git add *
logexec sudo -u $puppetuser git commit -a -m "initial commit after http://stdout.no/a-modern-puppet-master-from-scratch/"

logexec sudo chgrp -R puppet /etc/puppet/environments
logexec sudo chmod -R 2775 /etc/puppet/environments
#read
logexec git push -u origin production

logexec sudo service puppetmaster stop
logexec sudo service puppetmaster start

exitcode=0
loglog
sudo puppet agent --test || exitcode=$?

if [ "$exitcode" -ne "2" ]; then
	logmsg "Puppet agent generated error $exitcode; aborting"
	exit $exitcode
fi

logheredoc EOT
sudo tee /etc/puppet/puppetdb.conf <<'EOT'
[main]
port = 8081
soft_write_failure = false
EOT

$loglog
echo "server = $fqdn" | sudo tee -a /etc/puppet/puppetdb.conf

logexec sudo augtool -L -A --transform "Puppet incl /etc/puppet/puppet.conf" set "/files/etc/puppet/puppet.conf/main/pluginsync" true
logexec sudo augtool -L -A --transform "Puppet incl /etc/puppet/puppet.conf" rm "/files/etc/puppet/puppet.conf/main/reports" store,puppetdb

logexec sudo augtool -L -A --transform "Puppet incl /etc/puppet/puppet.conf" set "/files/etc/puppet/puppet.conf/master/storeconfigs" true
logexec sudo augtool -L -A --transform "Puppet incl /etc/puppet/puppet.conf" set "/files/etc/puppet/puppet.conf/master/storeconfigs_backend" puppetdb


logexec sudo mkdir -p /etc/facter/facts.d 
logheredoc EOT
sudo tee /etc/facter/facts.d/userlocation.json <<EOT >/dev/null
{
  "user": "$puppetuser",
  "location": "LxcOnAm"
}
EOT

if ! grep "export LANG=pl_PL.UTF-8" /etc/default/puppetmaster >/dev/null; then
	$loglog
	echo "export LANG=pl_PL.UTF-8" | sudo tee -a /etc/default/puppetmaster >/dev/null
	logexec sudo service puppetmaster restart 
fi

# kill $pingsudopid
