#!/bin/bash
cd `dirname $0`

#Program jest częścią zdalną tie-gitolite-with-puppet.sh.
#Program służy do konfiguracji puppetmastera tak, aby było połączone z puppetem.

#W szczególności, jeśli program jest uruchomiony w trybie lokalnym, to modyfikuje git hook tak, aby uruchamiane były przez użytkownika puppet.
#Poza tym, modyfikuje /etc/passwd aby dać użytkownikowi puppet shell.
#Poza tym, upewnia się, że ten użytkownik ma klucz i kopiuje część publiczną do tmp/puppet@puppetmaster.pub. 

. ./common.sh

alias errcho='>&2 echo'

puppetislocal=0
puppetsource="/srv/puppet.git"
puppetuser=puppet
debug=0

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--puppetmaster-is-local-to-gitolite)
	puppetislocal=1
	;;
	--puppet-local-repo)
	puppetsource=$1
	shift
	;;
	--puppetmaster-username)
	puppetuser=$1
	shift
	;;
	--debug)
	debug=1
	;;
	--log)
	log=$1
	shift
	;;
	*)
	echo "Unkown parameter '$key'. Aborting."
	exit 1
	;;
esac
done

#if [ "$puppetislocal" -eq 1 ] && [ -z "$gitoliteserver" ]; then
#	gitoliteserver=localhost
#	gitoliteuri=localhost
#fi

#if [ -z "$gitoliteserver" ]; then
#	errcho "you must specify --gitolite-server or --puppetmaster-is-local-to-gitolite"
#	exit 1
#fi

if [ "$puppetislocal" -eq "1" ]; then
	#/srv/puppet.git: Modyfikujemy post-receive hook tak, aby wykonywany był zawsze w imieniu puppet. Nie trzeba niczego modyfikować, jeśli wykonywani będziemy przez ssh z innego hosta - wtedy od razu będziemy prawidłowym użytkownikiem
	logexec sudo mv $puppetsource/hooks/post-receive $puppetsource/hooks/post-receive-as-puppet
	logheredoc EOT
	sudo tee $puppetsource/hooks/post-receive >/dev/null <<'EOT'
#!/bin/bash

curgroup=$(id -g -n $(whoami))

if [ "$curgroup" != "puppet" ]; then
    sudo -iu puppet `pwd`/hooks/post-receive-as-puppet
else
    `pwd`/hooks/post-receive-as-puppet
fi
EOT
	logexec sudo chmod +x $puppetsource/hooks/post-receive

	#gitolite: Upewniamy się, że użytkownik gitolite może stać się puppet w powyższym skrypcie bez konieczności podawania hasła
	$loglog
	echo "gitolite ALL = ($puppetuser) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/gitolite-puppet >/dev/null
fi

#Upewniamy się, że puppet może wykonywać polecenia (trochę niebezpieczne, być może później trzeba będzie te prawo mu odebrać)
logexec sudo sed -i -e "/$puppetuser\:.*\/bin\/false/ s/\/bin\/false/\/bin\/bash/" /etc/passwd

#if [ -n "$puppetrsa" ]; then
#	sshhome=`getent passwd $puppetuser | awk -F: '{ print $6 }'`
#	sudo cp $sshhome/.ssh/id_rsa.pub $puppetrsa
#	if [ $? -ne 0 ]; then
#		errcho "Cannot copy puppet's rsa pub key"
#		exit 1
#	fi
#fi

#if [ "$puppetislocal" -eq "0" ]; then
#	pubkeyplaceremote="/tmp/$puppetuser@puppetmaster.pub"
#	opts2=""

#	opts="--server-host $gitoliteserver --place-to-hold-ssh-pubkey $pubkeyplaceremote --client-target-account $puppetuser"

#	if [ "$debug" -eq "1" ]; then
#		opts2="$opts2 --debug"
#	fi
#	if [ -n "$log" ]; then
#		opts2="$opts2 --log $log"
#	fi
#	. ./execute-script-remotely.sh remote/ensure-ssh-access-on-client.sh $opts2 -- $opts
#fi

#sshhome=`getent passwd $puppetuser | awk -F: '{ print $6 }'`
#rsapath="$sshhome/.ssh/id_rsa"

#if sudo [ ! -f "$rsapath" ]; then
#	logexec sudo -u $puppetuser ssh-keygen -q -t rsa -N "" -f "$rsapath"
#	set -x
#fi
#rsapath="$rsapath.pub"
#logexec sudo cp $rsapath /tmp/puppet@puppetmaster.pub
#set -x

##Upewniamy się, że serwer gitolite nie będzie dla puppetmastera obcy
#sshhome=`getent passwd $puppetuser | awk -F: '{ print $6 }'`
#if [ -f "$sshhome/.ssh/known_hosts" ]; then
#	logexec sudo -u $puppetuser ssh-keygen -f "$sshhome/.ssh/known_hosts" -R $gitoliteserver 
#	set -x
#fi
#$loglog
#sudo -u $puppetuser ssh-keyscan -H $gitoliteserver | sudo -u $puppetuser tee -a $sshhome/.ssh/known_hosts 2>/dev/null
#set -x


# Bez tego nie będziemy mogli instalować modułów
logexec sudo chown -R $puppetuser:puppet /etc/puppet


