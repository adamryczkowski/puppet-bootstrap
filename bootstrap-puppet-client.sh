#!/bin/bash
cd `dirname $0`
 
. ./common.sh

#To jest skrypt, który zajmuje się instalacją samego klienta puppet.
#Skrypt bierze na siebie odpowiedzialność za instalację puppeta.

#syntax:
#bootstrap-puppet-client.sh <puppetmaster> [--debug] [--certname <alt cert name>] [--log <path>]
# --debug
# --log - ścieżka do pliku, w którym są zapisywane faktycznie wykonywane komendy oraz ich output

puppetmaster_name=$1
shift

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
certname=

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--debug)
	debug=1
	;;
	--certname)
	certname=$1
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

if [ -n "$log" ]; then
	if [ -f $log ]; then
		rm $log
	fi
fi

opts="--puppetmaster $puppetmaster_name"
opts2="--host localhost"
if [ -n "$log" ]; then
	opts2="$opts2 --log $log"
fi
if [ "$debug" -eq "1" ]; then
	optx="-x"
else
	optx=""
fi
. ./execute-script-remotely.sh remote/configure-puppetclient.sh $optx $opts2 -- $opts 
exitstat=$?
if [ $exitstat -ne 0 ]; then
	exit 1
fi

