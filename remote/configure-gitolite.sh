#!/bin/bash
cd `dirname $0`
. ./common.sh

#Ten skrypt zajmuje się konfiguracją gitolite.
#Poza samą instalacją gitolite3:
#* tworzy uprawnienia kompatybilne z puppetem, tj. tworzy wild repo w formie "puppet/*"
#* upewnia się, że lokalny użytkownik ma swój klucz publiczny
#* daje uprawnienia do modyfikowania repozytorium ustalonemu w argumentach użytkownikowi oraz użytkownikowi lokalnemu
#* upewnia się, że localhost jest znany przez ssh


#Gitolite służy jako serwer git, głównie na potrzeby Puppeta (r10k z niego pobiera najnowsze wersje modułów)

#./configure-gitolite.sh -u|--other-user <user name> <sciezka do pliku z kluczem publicznym dla tego użytkownika>

gitoliteuser=gitolite
user=`whoami`

sshhome=`getent passwd $user | awk -F: '{ print $6 }'`
rsapath="$sshhome/.ssh/id_rsa"


if [ ! -f "$rsapath" ]; then
	logexec ssh-keygen -q -t rsa -N "" -f "$rsapath"
fi
rsapath="$rsapath.pub"

while [[ $# > 0 ]]
do
	key="$1"
	shift

	case $key in
		-u|--other-user)
			otheruser="$1"
			otherrsapath="$2"
			shift 2
			;;
		--log)
			log=$1
			shift
			;;
		--debug)
			debug=1
			;;
		*)
			echo "Unknown parameter '$key'. Aborting."
			exit 1
			;;
	esac
done

if [ ! -f "$rsapath" ]; then
	echo "Cannot find rsa public key of the user. Create one with ssh-keygen or specify with --rsa-pub-path"
	exit 1
fi

if dpkg -s gitolite3 2>/dev/null >/dev/null; then
	echo "gitolite3 already installed!"
else
	logexec export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true
	logheredoc EOT
	tee /tmp/preseed.txt <<EOT >/dev/null
gitolite3    gitolite3/gitdir   string /var/lib/gitolite
gitolite3    gitolite3/adminkey string $rsapath
gitolite3    gitolite3/gituser  string gitolite
EOT
	logexec sudo debconf-set-selections /tmp/preseed.txt
	logexec sudo apt-get --yes install gitolite3
fi

fqdn=`hostname --fqdn`
hostname=`hostname`

if [ -f "$sshhome/.ssh/known_hosts" ]; then
	logexec ssh-keygen -f "$sshhome/.ssh/known_hosts" -R 127.0.0.1
	logexec ssh-keygen -f "$sshhome/.ssh/known_hosts" -R localhost
	logexec ssh-keygen -f "$sshhome/.ssh/known_hosts" -R $fqdn
	logexec ssh-keygen -f "$sshhome/.ssh/known_hosts" -R $hostname
fi

loglog
ssh-keyscan -H 127.0.0.1 >> $sshhome/.ssh/known_hosts
loglog
ssh-keyscan -H localhost >> $sshhome/.ssh/known_hosts
$loglog
ssh-keyscan -H $fqdn >> $sshhome/.ssh/known_hosts
$loglog
ssh-keyscan -H $hostname >> $sshhome/.ssh/known_hosts

tmpfolder=`mktemp -d --suffix .git`
cd $tmpfolder
logexec git clone gitolite@localhost:gitolite-admin
if [ -n "$otheruser" ]; then
	logexec cp $otherrsapath $tmpfolder/gitolite-admin/keydir/$otheruser.pub
fi

logheredoc EOT
tee $tmpfolder/gitolite-admin/conf/gitolite.conf <<EOT >/dev/null
repo gitolite-admin
    RW+     =   admin $otheruser

@puppetadmins  = admin $otheruser

include "conf.d/*.conf"
EOT

logexec mkdir -p $tmpfolder/gitolite-admin/conf/conf.d

logheredoc EOT
tee $tmpfolder/gitolite-admin/conf/conf.d/puppet-modules.conf <<'EOT' >/dev/null
repo puppet/..*
    C                           =   @puppetadmins
    RW+                         =   @puppetadmins
    R                           =   @all
EOT

logexec cd $tmpfolder/gitolite-admin
logexec git config --global push.default matching
logexec git add -A


exitcode=0
$loglog

if [ -z "$(git config --global user.email)" ]; then
	$loglog
	git config --global user.email "gitolite-admin@`hostname`"
fi
if [ -z "$(git config --global user.name)" ]; then
	logexec git config --global user.name "gitolite-admin"
fi

git commit -m "gitolite initial config update by ./configure-gitolite.sh" || exitcode=$?

logexec git push
cd ..
rm -r $tmpfolder
