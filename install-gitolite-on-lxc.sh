#!/bin/bash
cd `dirname $0`
. ./common.sh

#To jest skrypt, który tworzy konter LXC z gitolite wewnątrz. Skrypt zakłada, że przynajmniej istnieje użytkownik puppet.
#install-gitolite-on-lxc.sh --fqdn <fqdn> --lxc-name <container name> [--lxc-username <lxc user name>] [---s|--git-source <URI to git repository with manifests]  [-g|--git-user <user name>] [-h|--git-user-keypath <keypath>] [--other-lxc-opts <other options to make-lxc-node>] 

#--other-lxc-opts - other options forwarded to make-lxc-node. Can be e.g. --ip <ip address>, --username <username> --usermode, --release <release name>, --autostart, --apt-proxy. The script will always set the following options: "--hostname $fqdn --username $lxcusername"
#--fqdn - fqdn
#--debug|-d
#--lxc-name - lxc container name 
#--lxc-username - lxc user name
#-g|--git-user - user name of the external user that will be given rights to access to container. By default it is the user that invokes this script
#-h|--git-user-keypath - sciezka do pliku z kluczem publicznym dla tego użytkownika. By default it is the public ssh key of the user that invokes this script


debug=0
alias errcho='>&2 echo'


dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}



mypath=${0%/*}
mypath=`dir_resolve $mypath`

usermode=0

if [ ! -d "$gemcache" ]; then
	gemcache=
fi

while [[ $# > 0 ]]
do
key="$1"
shift
case $key in
	-d|--debug)
	debug=1
	;;
	--fqdn)
	fqdn=$1
	shift
	;;
	--lxc-name)
	lxcname="$1"
	shift
	;;
	--lxc-username)
	lxcusername="$1"
	shift
	;;
	-g|--git-user)
	gituser="$1"
	shift
	;;
	--usermode)
	usermode=1
	;;
	-h|--git-user-keypath)
	gituserrsapath="$1"
	shift
	;;
	--other-lxc-opts|--)
	otherlxcoptions="$*"
	shift $#
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

if [ -z "$lxcname" ]; then
	errcho "You must specify --lxc-name parameter"
	exit 1
fi

if [ -z "$lxcusername" ]; then
	lxcusername=`whoami`
fi

if [ -n "$gituserrsapath" ]; then
	if [ -z "$gituser" ]; then
		errcho "Cannot use --git-user-keypath if no --git-user is specified."
		exit 1
	fi
fi

if [ -z "$gituser" ]; then
	gituser=`whoami`
fi

if [ -z "$gituserrsapath" ]; then
	sshhome=`getent passwd $gituser | awk -F: '{ print $6 }'`
	if [ $? -ne 0 ]; then
		errcho "Cannot automatically find public certificate for user $gituser."
		exit 1
	fi
	gituserrsapath=$sshhome/.ssh/id_rsa.pub
fi

if [ ! -f "$gituserrsapath" ]; then
	errcho "Cannot find public certificate for user $gituser in $gituserpath. You can create one with \'ssh-keygen -q -t rsa -N \"\" -f \"$gituserrsapath\""
	exit 1
fi

if [ -z "$fqdn" ]; then
	errcho "When creating lxc containers you MUST provide --fqdn option"
	exit 1
fi


opts="--hostname $fqdn --username $lxcusername --autostart $otherlxcoptions"
if [ "$usermode" -eq "1" ]; then
	opts="$opts --usermode"
fi
opts2="--host localhost --extra-executable force-sudo.sh"
if [ -n "$log" ]; then
	opts2="$opts2 --log $log"
fi
if [ "$debug" -eq "1" ]; then
	optx="-x"
else
	optx=""
fi
. ./execute-script-remotely.sh ./make-lxc-node.sh $optx $opts2 -- $lxcname $opts
exitstat=$?
if [ $exitstat -ne 0 ]; then
	exit $xitstat
fi



if [ -n "$gituser" ]; then
	remotekeypath=/tmp/$gituser.pub
	logexec scp $gituserrsapath $lxcusername@$fqdn:$remotekeypath 
	gitoliteopts="--other-user $gituser $remotekeypath"
fi
opts2="--user $lxcusername --host $fqdn"
if [ "$debug" -eq "1" ]; then
	opts2="$opts2 --debug"
fi
if [ -n "$log" ]; then
	opts2="$opts2 --log $log"
fi
. ./execute-script-remotely.sh remote/configure-gitolite.sh $opts2 -- $gitoliteopts

#scp $gituserrsapath $lxcusername@$fqdn:$remotekeypath >/dev/null
#scp remote/configure-gitolite.sh $lxcusername@$fqdn:/tmp >/dev/null
#ssh $lxcusername@$fqdn "chmod +x /tmp/configure-gitolite.sh"
#if [ "$debug" -eq "1" ]; then
#	ssh $lxcusername@$fqdn "bash -x -- /tmp/configure-gitolite.sh $gitoliteopts"
#else
#	ssh $lxcusername@$fqdn "/tmp/configure-gitolite.sh $gitoliteopts"
#fi
exitstat=$?
if [ $exitstat -ne 0 ]; then
	exit $exitstat
fi

#ssh $lxcusername@$fqdn "sudo adduser gitolite puppet"  >/dev/null
#exitstat=$?
#if [ $exitstat -ne 0 ]; then
#	exit $exitstat
#fi

