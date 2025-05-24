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


#if ! sudo -n 'ls>/dev/null' 2>/dev/null; then
#	echo "No sudo permissions!"
#fi

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
	logexec sudo apt --yes install wget
fi

if ! dpkg -s augeas-tools>/dev/null 2>/dev/null; then
	logexec sudo apt --yes install augeas-tools
fi

if ! dpkg -s git>/dev/null 2>/dev/null; then
	logexec sudo apt --yes install git
fi

#TODO:
#sudo ufw allow 8140
#sudo systemctl start puppetserver
#sudo systemctl status puppetserver
#sudo systemctl enable puppetserver



source /etc/lsb-release

if [ ! -f /etc/apt/sources.list.d/puppetlabs-pc1.list ]; then
	if [ ! -f "/tmp/puppet-${DISTRIB_CODENAME}.deb" ]; then
		logexec curl https://apt.puppetlabs.com/puppetlabs-release-pc1-${DISTRIB_CODENAME}.deb -o /tmp/puppet-${DISTRIB_CODENAME}.deb
	fi
	logexec sudo dpkg -i "/tmp/puppet-${DISTRIB_CODENAME}.deb"
	logexec sudo apt-get update
	logexec rm /tmp/puppet-${DISTRIB_CODENAME}.deb
fi

if ! dpkg -s puppetserver >/dev/null  2>/dev/null; then
	logexec sudo apt-get --yes install puppetserver #puppetdb-terminus
fi

if [ ! -f /etc/profile.d/puppetserver.sh ]; then
	logheredoc EOT
	sudo tee /etc/profile.d/puppetserver.sh >/dev/null <<'EOT'
# Add /opt/puppetlabs/puppet/bin to the path for sh compatible users
if ! echo $PATH | grep -q /opt/puppetlabs/puppet/bin ; then
  export PATH=$PATH:/opt/puppetlabs/puppet/bin
fi
EOT
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


logexec sudo augtool  --autosave --noautoload --transform "Puppet incl /etc/puppetlabs/puppet/puppet.conf" set "/files/etc/puppetlabs/puppet/puppet.conf/master/trusted_server_facts" true
logexec sudo augtool  --autosave --noautoload --transform "Puppet incl /etc/puppetlabs/puppet/puppet.conf" set "/files/etc/puppetlabs/puppet/puppet.conf/master/strict_variables" true

logexec sudo systemctl enable puppetserver
logexec sudo service puppetserver start

#Now we are installing puppetdb
sudo service puppetserver stop

logexec sudo augtool  --autosave --noautoload --transform "Puppet incl /etc/puppetlabs/puppet/puppet.conf" set "/files/etc/puppetlabs/puppet/puppet.conf/master/storeconfigs" true
logexec sudo augtool  --autosave --noautoload --transform "Puppet incl /etc/puppetlabs/puppet/puppet.conf" set "/files/etc/puppetlabs/puppet/puppet.conf/master/storeconfigs_backend" puppetdb
logexec sudo augtool  --autosave --noautoload --transform "Puppet incl /etc/puppetlabs/puppet/puppet.conf" set "/files/etc/puppetlabs/puppet/puppet.conf/master/reports = store,puppetdbadam" store,puppetdb


logexec sudo augtool  --autosave --noautoload --transform "Puppet incl /etc/puppetlabs/puppet/puppetdb.conf" set "/files/etc/puppetlabs/puppet/puppetdb.conf/main/server_urls" "https://${fqdn}:8081"

logexec sudo /opt/puppetlabs/puppet/bin/puppet module install puppetlabs-puppetdb --version 5.1.2

logexec sudo apt install puppetdb-termini

logheredoc EOT
sudo tee /etc/puppetlabs/puppet/routes.yaml >/dev/null <<'EOT'
---
master:
  facts:
    terminus: puppetdb
    cache: yaml
EOT

logexec sudo /opt/puppetlabs/puppet/bin/puppet apply --execute  "class { 'puppetdb': listen_address => 'puppetmaster.statystyka.net'}"

logexec sudo /opt/puppetlabs/puppet/bin/puppet module install puppet-hiera --version 2.4.0

logexec sudo /opt/puppetlabs/puppet/bin/gem install hiera-eyaml

#logexec sudo /opt/puppetlabs/bin/puppetserver gem install hiera-eyaml
logexec sudo /opt/puppetlabs/puppet/bin/puppet apply --execute "class {'hiera': hierarchy => ['secure', '%{fqdn}', '%{environment}', 'common'], eyaml => true, provider => 'puppetserver_gem'}"


logexec sudo service puppetserver start
logexec sudo service puppetdb start

logexec sudo systemctl enable puppetdb

logexec sudo gem install librarian-puppet


exit 0

logheredoc EOT
sudo tee /etc/puppetlabs/puppet/hiera.yaml >/dev/null <<'EOT'
---
version: 5
defaults:  # Used for any hierarchy level that omits these keys.
  datadir: data         # This path is relative to hiera.yaml's directory.
  data_hash: yaml_data  # Use the built-in YAML backend.

hierarchy:
  - name: "Per-node data"
    path: "nodes/%{trusted.certname}.yaml"  # File path, relative to datadir.
                                   # ^^^ IMPORTANT: include the file extension!

  - name: "Secret data (encrypted)"
    lookup_key: eyaml_lookup_key   # Uses non-default backend.
    path: "secrets.eyaml"
    options:
      pkcs7_private_key: /etc/puppetlabs/puppet/eyaml/private_key.pkcs7.pem
      pkcs7_public_key:  /etc/puppetlabs/puppet/eyaml/public_key.pkcs7.pem

  - name: "Per-OS defaults"
    path: "os/%{facts.os.family}.yaml"

  - name: "Common data"
    path: "common.yaml"
EOT

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

logexec sudo service puppetserver restart

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
