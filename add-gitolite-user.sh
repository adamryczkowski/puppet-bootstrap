#!/bin/bash
cd `dirname $0`

#Adds user to the existing gitolite installation. Needs to be called as a user that has rights to modify gitolite's master repository.

#add-gitolite-user.sh --gitolite-host <gitolite address> --client-access <admin@client.host> [--client-target-account <target-user-name-on-client-host>] [--username-for-gitolite <username>] 
# -g|--gitolite-host - nazwa serwera gitolite
# --client-access - [admin@]server - host na którym żyje użytkownik.
# --client-target-account - nazwa użytkownika, jaką użytkownik loguje się na hoście klienckim. Jeśli nie podana, to używana jest ta sama nazwa co --client-access
# --username-for-gitolite - Nazwa użytkownika taka, jaką ma widzieć gitolite; być może po niej jest @ i jakiś identyfikator, np. adam@puppetmaster. Domyślnie właśnie taka nazwa jest tworzona.


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
server_host=""
client_account=""
client_access=""
log=""

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
	--username-for-gitolite)
	account_name_for_gitolite=$1
	shift
	;;
	--client-access)
	client_access=$1
	shift
	;;
	--client-target-account)
	client_account=$1
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

if [ -z "$server_host" ]; then
	errcho "You must eneter --server-host"
	exit 1
fi

if [ -z "$client_access" ]; then
	errcho "You must eneter --client-access parameter"
	exit 1
else
	if [[ "$client_access" =~ (.*)@(.*) ]]; then
		client_proxyuser="${BASH_REMATCH[1]}"
		client_host="${BASH_REMATCH[2]}"
	else
		client_proxyuser=`whoami`
		client_host="$server_access"
	fi
fi

if [ -z "$client_account" ]; then
	client_account="$client_proxyuser"
fi

if [ -z "$account_name_for_gitolite" ]; then
	account_name_for_gitolite="$client_account@$client_host"
fi



#Krok 1 - zbieramy certyfikat klienta, aby go zainstalować na serwerze oraz rejestrujemy host serwera na kliencie. 
if [ "$client_host" != "localhost" ]; then
	pubkeyplaceremote=`ssh $client_proxyuser@$client_host mktemp --dry-run --suffix=.pub`
else
	pubkeyplaceremote=`mktemp --dry-run --suffix=.pub`
fi
opts2="--user $client_proxyuser --host $client_host"

opts="--server-host $server_host --place-to-hold-ssh-pubkey $pubkeyplaceremote --client-target-account $client_account"

if [ "$debug" -eq "1" ]; then
	opts2="$opts2 --debug"
fi
if [ -n "$log" ]; then
	opts2="$opts2 --log $log"
fi
. ./execute-script-remotely.sh remote/ensure-ssh-access-on-client.sh $opts2 -- $opts

#Krok 2 - pobieramy certyfikat klienta z klienta
if [ "$client_host" != "localhost" ]; then
	pubkeyfile=`mktemp --dry-run --suffix=.pub`
	logexec scp $client_proxyuser@$client_host:$pubkeyplaceremote $pubkeyfile
	logexec ssh $client_proxyuser@$client_host sudo rm $pubkeyplaceremote
else
	pubkeyfile="$pubkeyplaceremote"
fi

#Krok 3 - instalujemy pobrany certyfikat klienta na repozytorium gitolite-admin
if ! dpkg -s git>/dev/null  2> /dev/null; then
    logexec sudo apt-get --yes install git
fi

gitoliteadminpath=`mktemp -d`
mydir=`pwd`
pushd $gitoliteadminpath >/dev/null
if [ $? -ne 0 ]; then
	errcho "Cannot create temporary directory"
	exit 1
fi

logexec git clone gitolite@$server_host:gitolite-admin
if [ $? -ne 0 ]; then
	errcho "Cannot connect with gitolite-admin. Are you sure the user `whoami` has a right to do that??"
	exit 1
fi
gitoliteadminpath="$gitoliteadminpath/gitolite-admin"

logexec cp $pubkeyfile $gitoliteadminpath/keydir/$account_name_for_gitolite.pub
if [ $? -ne 0 ]; then
	errcho "Cannot copy the key into gitolite's admin directory"
	exit 1
fi

logexec cd $gitoliteadminpath
logexec git add .
if [ -n "$(git status --porcelain)" ]; then
	if [ "$(git config --global push.default)" != "matching" ]; then
		logexec git config --global push.default matching
	fi
	if [ -z "$(git config --global user.email)" ]; then
		$loglog
		git config --global user.email "`whoami`@`hostname`"
	fi
	if [ -z "$(git config --global user.name)" ]; then
		$loglog
		git config --global user.name "`whoami`"
	fi
	logexec git commit -m "Added user $account_name_for_gitolite."
	if [ $? -ne 0 ]; then
		logexec git config --global user.email "`whoami`@`hostname`"
		logexec git config --global user.name "`whoami`"
		logexec git commit -m "Added user $account_name_for_gitolite."
	fi
	logexec git push
fi
popd >/dev/null
sudo rm -r `dirname $gitoliteadminpath`


