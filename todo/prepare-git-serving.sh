#!/bin/bash
cd `dirname $0`
. ./common.sh

#To jest skrypt, który przygotowywuje serwer do bootstrapowania

#syntax:
#prepare-git-serving.sh -r|--repository-base-path <ścieżka do katalogu z bare repositories, które mamy serwować.> [--signal-pipe]

stand_alone=1

while [[ $# > 0 ]]
do
	key="$1"
	shift

	case $key in
		--signal-pipe)
			pipe=$1
			stand_alone=0
			shift
			;;
		-r|--repository-base-path)
			puppetrepo=$1
			shift
			;;
		*)
			echo "Unkown parameter '$key'. Aborting."
			exit 1
			;;
	esac
done

if [ ! -d "$puppetrepo" ]; then
	echo "Missing or inaccessible repository path. Must be an existing path to folder with all bare repositories to serve."
	exit 1
fi


function dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}



mypath=${0%/*}
mypath=`dir_resolve $mypath`


if dpkg -s git>/dev/null 2>/dev/null; then
	echo "git already installed!"
else
	sudo apt-get --yes install git
fi

if dpkg -s rsync>/dev/null 2>/dev/null; then
	echo "rsync already installed!"
else
	sudo apt-get --yes install rsync
fi

git daemon --verbose --base-path="$puppetrepo" --export-all --informative-errors --enable=receive-pack
#exitstat=$?
#if [ $exitstat -ne 0 ]; then
#	echo $exitstat >$pipe
#	exit $exitstat
#fi

#childpid=$!

#function catch_exit() {
#	kill $childpid
#}
#trap catch_exit EXIT SIGINT

#if [ $stand_alone -eq 0 ]; then
#	echo ok >$pipe
#fi

# sleep 10000
