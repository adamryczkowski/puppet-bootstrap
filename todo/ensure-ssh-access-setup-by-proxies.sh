#!/bin/bash
cd `dirname $0`

#Ten skrypt upewnia się, że możliwy będzie dostęp z zadanego adresu ssh A do drugiego adresu ssh B (serwer) bez podawania haseł.
#Skrypt wykonuje pracę z poziomu innego hosta i konta C, który ma dostęp ssh do obu kont.

#syntax:
#ensure-ssh-access-setup-by-proxies --server-access <adres ssh do serwera, który jest dostępny dla nas i - jeśli konto jest inne - ma uprawnienia sudo > --server-target-account <konto klienta na serwerze. Jeśli nie podane, to przyjmuje się to samo co server-access> --client-access <working ssh address on client> --client-target-account <jeśli inne niż client-access, nazwa konta klienta>
# --server-access - adres ssh do serwera, który jest dostępny dla nas i - jeśli konto jest inne - ma uprawnienia sudo. Można podać port w formie ssh://[user@]server[:port]
# --server-target-account - opcjonalny parametr. Konto klienta na serwerze. Jeśli nie podane, to przyjmuje się to samo co server-access
# --client-access - adres ssh do klienta, który jest dostępny dla nas i - jeśli konto jest inne - ma uprawnienia sudo ssh://[user@]server[:port]
# --client-target-account - opcjonalny parametr. Konto klienta na kliencie. Jeśli nie podane, to przyjmuje się to samo co client-access


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
server_account=""
client_account=""
server_access=""
client_access=""
log=""
hostkey_only=0

while [[ $# > 0 ]]
do
	key="$1"
	shift

	case $key in
		--debug)
			debug=1
			;;
		--server-access)
			server_access=$1
			shift
			;;
		--server-target-account)
			server_account=$1
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
		--only-host-key)
			hostkey_only=1
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

uri_regex="((git)|(ssh)\:\/?\/?)?([[:alnum:]]+)@([[:alnum:]\.]+)(\:([[:digit:]]+))?"

if [[ "$server_access" =~ $regex ]]; then
	server_proxyuser="${BASH_REMATCH[4]}"
	server_host="${BASH_REMATCH[5]}"
	server_port="${BASH_REMATCH[7]}"
else
	errcho "You must eneter --server-access parameter"
	exit 1
fi

if [ -z "$server_proxyuser" ]; then
	server_proxyuser=`whomi`
fi

if [ -z "$server_port" ]; then
	server_port=22
fi

if [ "$server_port" != "22" ]; then
	server_portarg1="-p $server_port"
	server_portarg2="-P $server_port"
else
	server_portarg1=
	server_portarg2=
fi

if [ -z "$server_account" ]; then
	server_account="$server_proxyuser"
fi


if [[ "$client_access" =~ $regex ]]; then
	client_proxyuser="${BASH_REMATCH[4]}"
	client_host="${BASH_REMATCH[5]}"
	client_port="${BASH_REMATCH[7]}"
else
	errcho "You must eneter --client-access parameter"
	exit 1
fi

if [ -z "$client_proxyuser" ]; then
	client_proxyuser=`whomi`
fi

if [ -z "$client_port" ]; then
	client_port=22
fi

if [ "$client_port" != "22" ]; then
	client_portarg1="-p $client_port"
	client_portarg2="-P $client_port"
else
	client_portarg1=
	client_portarg2=
fi

if [ -z "$client_account" ]; then
	client_account="$client_proxyuser"
fi


#Krok 1 - zbieramy certyfikat klienta, aby go zainstalować na serwerze oraz rejestrujemy host serwera na kliencie.
opts="--server-host $server_host --client-target-account $client_account"
if [ "$hostkey_only" -eq "0" ]; then
	if [ "$client_host" != "localhost" ]; then
		pubkeyplaceremote=`ssh $client_portarg1 $client_proxyuser@$client_host mktemp --dry-run --suffix=.pub`
	else
		pubkeyplaceremote=`mktemp --dry-run --suffix=.pub`
	fi
	opts="$opts --place-to-hold-ssh-pubkey $pubkeyplaceremote"
fi

opts2="--user $client_proxyuser --host $client_host  --port $client_port"
if [ "$debug" -eq "1" ]; then
	opts2="$opts2 --debug"
fi
if [ -n "$log" ]; then
	opts2="$opts2 --log $log"
fi
. ./execute-script-remotely.sh remote/ensure-ssh-access-on-client.sh $opts2 -- $opts

if [ "$hostkey_only" -eq "1" ]; then
	exit 0
fi

#Krok 2 - pobieramy certyfikat klienta z klienta
if [ "$client_host" != "localhost" ]; then
	pubkeyfile=`mktemp --dry-run --suffix=.pub`
	logexec scp $client_portarg2 $client_proxyuser@$client_host:$pubkeyplaceremote $pubkeyfile
	logexec ssh $client_portarg1 $client_proxyuser@$client_host sudo rm $pubkeyplaceremote
else
	pubkeyfile="$pubkeyplaceremote"
fi

#Krok 3 - kopiujemy pobrany certyfikat klienta na serwerze
if [ "$server_host" != "localhost" ]; then
	pubkeysrv=`ssh $server_portarg1 $server_proxyuser@$server_host mktemp --dry-run --suffix=.pub`
	logexec scp $server_portarg2 $pubkeyfile $server_proxyuser@$server_host:$pubkeysrv
	logexec rm $pubkeyfile
else
	pubkeysrv="$pubkeyfile"
fi

#Krok4 - instalujemy pobrany certyfikat klienta na serwerze
opts2="--user $server_proxyuser --host $server_host --port $server_port"

opts="--ssh-key-file $pubkeysrv --server-target-account $server_account"
if [ "$debug" -eq "1" ]; then
	opts2="$opts2 --debug"
fi
if [ -n "$log" ]; then
	opts2="$opts2 --log $log"
fi
. ./execute-script-remotely.sh remote/ensure-ssh-access-on-server.sh $opts2 -- $opts

if [ "$server_host" != "localhost" ]; then
	logexec ssh $server_portarg1 $server_proxyuser@$server_host sudo rm $pubkeysrv
else
	logexec sudo rm $pubkeysrv
fi
