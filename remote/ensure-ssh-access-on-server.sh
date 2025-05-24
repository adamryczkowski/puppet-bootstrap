#!/bin/bash
cd `dirname $0`

#Ten skrypt wykonuje się z poziomu serwera ssh, ale nie koniecznie z konta, które ma klient dostać dostęp.

#Skrypt instaluje część serwerową połączenia, tj. upewnia się, że ssh serwer jest zainstalowany, oraz dodaje certyfikat klienta do authorized_keys.

#syntax:
#ensure-ssh-access-on-server.sh --ssh-key <klucz> --server-target-account <server target account>
# --ssh-key - plik lub string z kluczem ssh
# --server-target-account - nazwa konta serwera, na którą pozwalamy się logować klientowi

. ./common.sh

alias errcho='>&2 echo'
function dir_resolve()
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
pubkeyfile=""
server_account="$(whoami)"

while [[ $# > 0 ]]
do
	key="$1"
	shift

	case $key in
		--debug)
			debug=1
			;;
		--ssh-key-file)
			pubkeyfile=$1
			shift
			;;
		--server-target-account)
			server_account=$1
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

if [ -z "$pubkeyfile" ]; then
	errcho "You must eneter --ssh-key parameter"
	exit 1
fi

if ! dpkg -s openssh-server>/dev/null  2> /dev/null; then
	logexec sudo apt-get --yes install openssh-server
fi

sshhome=`getent passwd $server_account | awk -F: '{ print $6 }'`
if sudo -u $server_account [ ! -d $sshhome/.ssh ]; then
	logexec sudo -u $server_account mkdir $sshhome/.ssh
fi
if sudo -u $server_account [ ! -f $sshhome/.ssh/authorized_keys ]; then
	$loglog
	cat $pubkeyfile | sudo -u $server_account tee $sshhome/.ssh/authorized_keys
else
	pubkey=`cat $pubkeyfile`
	klucz=`echo $pubkey | awk '{ print $2 }'`
	if ! sudo -u $server_account grep "^[^#]" $sshhome/.ssh/authorized_keys  | awk '{ print $2 }' | grep $klucz; then
		echo "Dodaję klucz"
		$loglog
		echo $pubkey | sudo -u $server_account tee -a $sshhome/.ssh/authorized_keys
	fi
fi
