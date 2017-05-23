#!/bin/bash
cd `dirname $0`
. ./common.sh


# syntax:
# bootstrap-server [--fqdn <fqdn>] [--debug|-d] [--lxc-config <lxc container name> <lxc user name>] --other-lxc-opts <other options forwarded to make-lxc-node> ] [---s|--git-source <URI to pre-existing git repository with manifests. Since it is puppetmaster who keeps full git repository, the git-source repository is imported on top of existing skeleton repository, retaining all history and branches] [--conf-puppet-opts <dodatkowe opcje do przekazania skryptowi configure-puppetmaster>] [-g|--git-user <user name>] [-h|--git-user-keypath <sciezka do pliku z kluczem publicznym dla tego użytkownika>] [--r10k-gems-path <path to the gem cache. Useful if no or little internet is available>] [--import-into-gitolite-server <ssh-compatible address of gitolite server, when we want to push the resulting main repository>]


debug=0



dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}
mypath=${0%/*}
mypath=`dir_resolve $mypath`
cd $mypath


gemcache=$mypath/r10k-gems

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
	--lxc-config)
	lxcname="$1"
	lxcusername="$2"
	shift 2
	;;
	--other-lxc-opts)
	otherlxcoptions="$1"
	shift
	;;
	-s|--git-source)
	gitsource="$1"
	shift
	;;
	--conf-puppet-opts)
	otherpuppetopts="$1"
	shift
	;;
	-g|--git-user)
	gituser="$1"
	shift
	;;
	-h|--git-user-keypath)
	gituserrsapath="$1"
	shift
	;;
	--r10k-gems-cache)
	gemcache="$1"
	shift
	;;
	*)
	echo "Unkown parameter '$key'. Aborting."
	exit 1
	;;
esac
done


if [ -z "$gituser" ]; then
	gituser=`whoami`
fi

if [ -z "$gituserrsapath" ]; then
	sshhome=`getent passwd $gituser | awk -F: '{ print $6 }'`
	if [ $? -ne 0 ]; then
		echo "Cannot automatically find public certificate for user $gituser."
		exit 1
	fi
	gituserrsapath=$sshhome/.ssh/id_rsa.pub
fi

if [ ! -f "$gituserrsapath" ]; then
	echo "Cannot find public certificate for user $gituser in $gituserpath. You can create one with \'ssh-keygen -q -t rsa -N \"\" -f \"$gituserrsapath\""
	exit 1
fi

if [ -n "$lxcname" ]; then
	if [ -z "$fqdn" ]; then
		echo "When creating lxc containers you MUST provide --fqdn option"
		exit 1
	fi
#	sudo lxc-stop -n $lxcname
#	sudo lxc-destroy -n $lxcname
	if [ "$debug" -eq "1" ]; then
		bash -x -- ./make-lxc-node.sh $lxcname --debug -h $fqdn -u $lxcusername $otherlxcoptions
	else
		./make-lxc-node.sh $lxcname -h $fqdn -u $lxcusername $otherlxcoptions
	fi
	exitstat=$?
	if [ $exitstat -ne 0 ]; then
		exit $exitstat
	fi



	if [ -d "$gemcache" ]; then
		ssh $lxcusername@$fqdn "mkdir /tmp/gemcache"
		scp -r "$gemcache" $lxcusername@$fqdn:/tmp/gemcache >/dev/null
		otherpuppetopts="$otherpuppetopts --r10k-gems-cache /tmp/gemcache/`basename $gemcache`"
	fi

	scp remote/configure-puppetmaster.sh $lxcusername@$fqdn:/tmp  >/dev/null
	ssh $lxcusername@$fqdn "sudo addgroup puppet; sudo adduser $lxcusername puppet"  >/dev/null
	ssh $lxcusername@$fqdn "chmod +x /tmp/configure-puppetmaster.sh"
	if [ "$debug" -eq "1" ]; then
		ssh $lxcusername@$fqdn "bash -x -- /tmp/configure-puppetmaster.sh  $otherpuppetopts"
	else
		ssh $lxcusername@$fqdn "/tmp/configure-puppetmaster.sh $otherpuppetopts"
	fi
	exitstat=$?
	if [ $exitstat -ne 0 ]; then
		exit $exitstat
	fi



	if [ -n "$gituser" ]; then
		remotekeypath=/tmp/$gituser.pub
		scp $gituserrsapath $lxcusername@$fqdn:$remotekeypath >/dev/null
		gitoliteopts="--other-user $gituser $remotekeypath"
	fi
	scp $gituserrsapath $lxcusername@$fqdn:$remotekeypath >/dev/null
	scp remote/configure-gitolite.sh $lxcusername@$fqdn:/tmp >/dev/null
	ssh $lxcusername@$fqdn "chmod +x /tmp/configure-gitolite.sh"
	if [ "$debug" -eq "1" ]; then
		ssh $lxcusername@$fqdn "bash -x -- /tmp/configure-gitolite.sh $gitoliteopts"
	else
		ssh $lxcusername@$fqdn "/tmp/configure-gitolite.sh $gitoliteopts"
	fi
	exitstat=$?
	if [ $exitstat -ne 0 ]; then
		exit $exitstat
	fi
	ssh $lxcusername@$fqdn "sudo adduser gitolite puppet"  >/dev/null
else
	if [ -n "$gituser" ]; then
		gitoliteopts="--other-user $gituser $gituserrsapath"
	fi

	if [ -d "$gemcache" ]; then
		otherpuppetopts="$otherpuppetopts --r10k-gems-cache $gemcache"
	fi

	if [ "$debug" -eq "1" ]; then
		bash -x -- ./configure-puppetmaster.sh -d `basename $fqdn` $otherpuppetopts
		exitstat=$?
		if [ $exitstat -ne 0 ]; then
			exit $exitstat
		fi
		bash -x -- ./configure-gitolite.sh $gitoliteopts
		exitstat=$?
		if [ $exitstat -ne 0 ]; then
			exit $exitstat
		fi
	else
		./configure-puppetmaster.sh -d `basename $fqdn` $otherpuppetopts
		exitstat=$?
		if [ $exitstat -ne 0 ]; then
			exit $exitstat
		fi
		./configure-gitolite.sh $gitoliteopts
		exitstat=$?
		if [ $exitstat -ne 0 ]; then
			exit $exitstat
		fi
	fi
	sudo adduser gitolite puppet
fi


