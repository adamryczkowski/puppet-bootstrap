#!/bin/bash
cd `dirname $0`
. ./common.sh

#Ten skrypt importuje istniejące repozytorium git do gitolite. Uruchamia się go z poziomu dowolnego serwera; skrypt sam się łączy z serwerem gitolite; wymaga jednak dostępu ssh

#./import-into-gitolite.sh --ssh-address <ssh-compatible URI to the gitolite server; work best if user don't need password to enter. It works even better, if this remote user is within the grace period of sudo or is root> <git-compatible path to the existing repository> <intended name of the target repository WITHOUT the .git suffix> [-c|--creator <user name of the creator - needed only if this is a wild repository>] [--debug] [-l|--local]

#--local means that the gitaddress is local to the gitolite server.
#--git-repo-uri - URI do naszego repozytorium takie, aby rozumiał je serwer gitolite (lub, jeśli ustawimy --git-repo-uri-not-accessible-from-gitolite - host wywołujący ten skrypt)
#--ssh-address - Adres SSH do serwera gitolite; konieczny, gdyż musimy wykonać pracę na serwerze. Gitolite nie obsługuje dodawania repozytoriów w inny sposób
#--reponame - Docelowa nazwa repozytorium BEZ sufiksu git
#--git-repo-uri-not-accessible-from-gitolite - jeśli ustawione, to repozytorium zostanie najpierw sklonowane na hoście wywołującym skrypt, następnie przeniesione do gitolite używając ssh, a dopiero stamtąd włożone na właściwe miejsce. Origin zostanie ustawiony na puste, chyba że ustawimy je ręcznie poprzez.
#--local - jeśli ustawione, oznacza że repozytorium jest 
#--remote-origin - adres repozytorium.


gitoliteuser=gitolite
debug=0
locally=0
copybyrsync=0

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--git-repo-uri-not-accessible-from-gitolite)
	copybyrsync=1
	;;
	--ssh-address)
	server=$1
	shift
	;;
	--git-repo-uri)
	gitaddress=$1
	shift
	;;
	--reponame)
	gitname=$1
	shift
	;;
	--debug)
	debug=1
	;;
	-c|--creator)
	creatorname="$1"
	shift 1
	;;
	-l|--locally)
	locally=1
	;;
	--remote-origin)
	remoteorigin=$1
	shift
	;;
	--log)
	log=$1
	shift
	;;
	*)
	echo "Unknown parameter '$key'. Aborting."
	exit 1
	;;
esac
done

if [ -z "$server" ]; then
	errcho "User did not specified --ssh-address. Aborting."
	exit 1
fi

if [[ "$server" =~ (.*)@(.*) ]]; then
	serveruser=${BASH_REMATCH[1]}
	serverhost=${BASH_REMATCH[2]}
else
	serveruser=`whoami`
	serverhost=$server
fi


if [ -z "$gitaddress" ]; then
	errcho "User did not specified --git-repo-uri. Aborting."
	exit 1
fi

if [ -z "$gitname" ]; then
	errcho "User did not specified --reponame. Aborting."
	exit 1
fi

if ! dpkg -s git>/dev/null 2>/dev/null; then
	logexec sudo apt-get --yes install git
fi


dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}

mypath=${0%/*}
mypath=`dir_resolve $mypath`

if [[ "$mypath" != "" ]]; then
	mypath=${mypath}/
fi

if [ "$copybyrsync" -eq "1" ]; then
#Musimy skopiować repozytorium na lokalny serwer. Nie zakładamy, że serwer gitolite ma dostęp do naszego repozytorium - może być za firewallem.
	tmprepo=`mktemp -d --suffix .git`
	logexec git clone --bare "$gitaddress" $tmprepo
	if [ "$debug" -eq "1" ]; then
		logexec rsync -avz $tmprepo $server:/tmp
	else
		logexec rsync -az $tmprepo $server:/tmp
	fi
	logexec rm -rf $tmprepo
else
	tmprepo=$gitaddress
fi

#if [ "$locally" -eq "0" ]; then
##Musimy skopiować repozytorium na lokalny serwer. Nie zakładamy, że serwer gitolite ma dostęp do naszego repozytorium - może być za firewallem.
#	tmprepo=`mktemp -d --suffix .git`

#	git clone --bare "$gitaddress" $tmprepo
#	cd $tmprepo
#	tar -cjf $tmprepo.tar.gz .

#	ssh $server mkdir -p /tmp/$gitname
#	scp $tmprepo.tar.gz $server:/tmp/$gitname.tar.gz  >/dev/null
#	sudo rm -r $tmprepo
#	ssh $server tar -xjf /tmp/$gitname.tar.gz -C /tmp/$gitname
#	tmprepo=/tmp/$gitname
#else
#	tmprepo=$gitaddress
#fi


opts="--repo-path $tmprepo --repo-name $gitname"
if [ -n "$creatorname" ]; then
	opts="$opts --creator-name $creatorname"
fi
if [ -n "$remoteorigin" ]; then
	opts="$opts --remote-origin $remoteorigin"
fi
opts2="--user $serveruser --host $serverhost"
if [ "$debug" -eq "1" ]; then
	opts2="$opts2 --debug"
fi
if [ -n "$log" ]; then
	opts2="$opts2 --log $log"
fi
. ./execute-script-remotely.sh remote/add-existing-repo.sh $opts2 -- $opts
#scp ${mypath}remote/add-existing-repo.sh $server:/tmp  >/dev/null
#ssh $server chmod +x /tmp/add-existing-repo.sh
#if [ "$debug" -eq "1" ]; then
#	ssh $server bash -x -- /tmp/add-existing-repo.sh $opts
#else
#	ssh $server /tmp/add-existing-repo.sh $opts
#fi


