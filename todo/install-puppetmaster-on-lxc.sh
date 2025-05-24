#!/bin/bash
cd `dirname $0`
. ./common.sh

#To jest skrypt, który tworzy konter LXC z konfiguruje puppetmaster wewnątrz.
#install-puppetmaster-on-lxc.sh [--fqdn <fqdn>] [--debug|-d] --lxc-name <lxc container name> [--lxc-username <lxc user name>] --other-lxc-opts <other options to make-lxc-node> ] [--conf-puppet-opts <other options to configure-puppetmaster>] [-g|--git-user <user name>] [-h|--git-user-keypath <keypath>] [--r10k-gems-path <path to the gem cache>] [--import-into-gitolite-server <ssh-compatible address of gitolite server>]
#--fqdn - fqdn
#--debug|-d
#--lxc-name - lxc container name
#--lxc-username - lxc user name
#--other-lxc-opts - other options forwarded to make-lxc-node
#--conf-puppet-opts - dodatkowe opcje do przekazania skryptowi configure-puppetmaster
#--r10k-gems-path - path to the gem cache. Useful if no or little internet is available




debug=0



function dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}



mypath=${0%/*}
mypath=`dir_resolve $mypath`


gemcache=$mypath/r10k-gems
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
		--usermode)
			usermode=1
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
		--other-lxc-opts|--)
			otherlxcoptions="$*"
			shift $#
			;;
		--conf-puppet-opts)
			otherpuppetopts="$1"
			shift
			;;
		--r10k-gems-cache)
			gemcache="$1"
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


if [ -z "$fqdn" ]; then
	echo "When creating lxc containers you MUST provide --fqdn option"
	exit 1
fi
opts="-h $fqdn -u $lxcusername --autostart $otherlxcoptions"
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

if [ -d "$gemcache" ]; then
	logexec ssh $lxcusername@$fqdn "mkdir /tmp/gemcache"
	logexec scp -r "$gemcache" $lxcusername@$fqdn:/tmp/gemcache
	otherpuppetopts="$otherpuppetopts --r10k-gems-cache /tmp/gemcache/`basename $gemcache`"
fi

logexec ssh $lxcusername@$fqdn "sudo addgroup puppet; sudo adduser $lxcusername puppet"

opts2="--user $lxcusername --host $fqdn"
if [ "$debug" -eq "1" ]; then
	opts2="$opts2 --debug"
fi
if [ -n "$log" ]; then
	opts2="$opts2 --log $log"
fi
. ./execute-script-remotely.sh remote/configure-puppetmaster.sh $opts2 -- $otherpuppetopts
#scp remote/configure-puppetmaster.sh $lxcusername@$fqdn:/tmp  >/dev/null
#ssh $lxcusername@$fqdn "chmod +x /tmp/configure-puppetmaster.sh"
#if [ "$debug" -eq "1" ]; then
#	ssh $lxcusername@$fqdn "bash -x -- /tmp/configure-puppetmaster.sh  $otherpuppetopts"
#else
#	ssh $lxcusername@$fqdn "/tmp/configure-puppetmaster.sh $otherpuppetopts"
#fi
exitstat=$?
if [ $exitstat -ne 0 ]; then
	exit $exitstat
fi
