#!/bin/bash
cd `dirname $0`

#Ten skrypt wykonuje się z poziomu klienta ssh, ale nie koniecznie z konta, które ma dostać dostęp. 

#Skrypt instaluje część kliencką połączenia, tj. akceptuje host servera ssh, upewnia się, że klient ma certyfikat i pobiera go aby przekazać serwerowi.

#syntax:
#ensure-ssh-access-on-client.sh --server-host <hostname> [--place-to-hold-ssh-pubkey <local path>] --client-target-account <user name>
# --server-host - host serwera, bez nazwy konta
# --client-target-account - nazwa użytkownika, który ma mieć dostęp do serwera
# --place-to-hold-ssh-pubkey - Lokalna ścieżka, na którą zostanie skopiowany certyfikat klienta. Ma sens, jeśli podaliśmy --dont-contact-server i skrypt nie może sam zainstalować certyfikatu. Jeśli się jej nie poda, to skrypt w ogóle nie ruszy certyfikatów użytwkownika

. ./common.sh

alias errcho='>&2 echo'
dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}
mypath=${0%/*}
mypath=`dir_resolve $mypath`
cd $mypath

debug=0
#1 - remote host.
#2 - localhost
#3 - lxc node
client_account="$(whoami)"
server_host=""
pubkeycopy=""

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--debug)
	debug=1
	;;
	--server-host)
	server_host=$1
	shift
	;;
	--client-target-account)
	client_account=$1
	shift
	;;
	--place-to-hold-ssh-pubkey)
	pubkeycopy=$1
	shift
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

if [ -z "$client_account" ]; then
	errcho "You must eneter --client-target-account parameter"
	exit 1
fi

if [ -z "$server_host" ]; then
	errcho "You must eneter --server-host parameter"
	exit 1
fi

sshhome=`getent passwd $client_account | awk -F: '{ print $6 }'`

# Upewniamy się, że u klienta host jest dodany do listy akceptowalnych hostów
echo "Adding the server to the client's known_hosts file..."
if sudo -u $client_account [ -f "$sshhome/.ssh/known_hosts" ]; then
	$loglog
	sudo -u $client_account ssh-keygen -f "$sshhome/.ssh/known_hosts" -R $server_host 
else
	if ! sudo -u $client_account [ -d "$sshhome/.ssh" ]; then
		logexec sudo -u $client_account mkdir "$sshhome/.ssh"
	fi
fi
$loglog
ssh-keyscan -H $server_host | sudo -u $client_account tee -a $sshhome/.ssh/known_hosts

if [ -z "$pubkeycopy" ]; then
	exit 0
fi


#Upewniamy się, że są wygenerowane klucze dla nas
if sudo -u $client_account [ ! -f "$sshhome/.ssh/id_rsa" ]; then
	$loglog
	sudo -u $client_account ssh-keygen -q -t rsa -N "" -f "$sshhome/.ssh/id_rsa"
	if [ $? -ne 0 ]; then
		exit 1
	fi
fi
logexec sudo -u $client_account cp $sshhome/.ssh/id_rsa.pub $pubkeycopy
logexec sudo chown $(whoami) $pubkeycopy


