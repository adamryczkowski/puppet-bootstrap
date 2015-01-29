#!/bin/bash
cd `dirname $0`
. ./common.sh

#Ten skrypt upewnia się, że dany użytkownik jest w grace period ssh. 

#syntax:
#force-sudo.sh <container-name> -l|--lxcusername <username> [--lxcowner <username>]
#--lxcusername - username inside the container, for whom we want to grant sudo rights
#--lxcowner - owner of the container. Defaults to the calling user. If owner=root, then it is assumed the lxc container is privileged.


name=$1
lxcuser=
lxcowner=
fixsudo=
usermode=0
shift

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	-l|--lxcusername)
	lxcuser="$1"
	shift
	;;
	--lxcowner)
	lxcowner="$1"
	shift
	;;
	--grant-nopasswd-sudo)
	fixsudo=1
	;;
	--revoke-nopasswd-sudo)
	fixsudo=0
	;;
	--usermode)
	usermode=1
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

if [ "$lxcuser" == "" ]; then
	echo "You must set --lxcusername parameter!" >2&
	exit 1
fi

if [ "$usermode" -eq "0" ]; then
	if [ -n "$lxcowner" ]; then
		if [ "$lxcowner" != "root" ]; then
			usermode=1
		fi
	fi
fi


if [ "$usermode" -eq "0" ]; then
	lxcowner=root
	sudoprefix="sudo"
	lxcpath=/var/lib/lxc/$name
else
	sudoprefix=
	if [ -z "$lxcowner" ]; then
		lxcowner=`whoami`
	fi
	sshhome=$(getent passwd $lxcowner | awk -F: '{ print $6 }')
	lxcpath=$sshhome/.local/share/lxc/$name
fi

if [ -n "$fixsudo" ]; then
	if [ "$fixsudo" -eq "1" ]; then
		if [ ! -f "$lxcpath/etc/sudoers.d/fix-$lxcuser" ]; then
			echo "Granting nopasswd sudo right for $lxcuser on $name..."
			$loglog
			echo "$lxcuser ALL = (root) NOPASSWD: ALL" | sudo tee $lxcpath/etc/sudoers.d/fix-$lxcuser >/dev/null
		fi
	else
		if [ -f "$lxcpath/etc/sudoers.d/fix-$lxcuser" ]; then
			echo "Removing nopasswd sudo right from $lxcuser on $name..."
			logexec $sudoprefix rm "$lxcpath/etc/sudoers.d/fix-$lxcuser"
		fi
	fi
else
	echo "Making sure, that for the next 15 minutes user can do sudo without the password (to be able to execute scripts with sudo)..."
	if sudo [ ! -d "$lxcpath/rootfs/var/lib/sudo/$lxcuser" ]; then
		logexec sudo mkdir $lxcpath/rootfs/var/lib/sudo/$lxcuser 2>/dev/null
	fi
	if [ -f "max-subuid.sh" ]; then
		subuid="`bash max-subuid.sh --user $lxcowner --subuid --show`"
		if [ "$?" -eq "1" ]; then
			echo "Cannot find subuid for the user. Exiting."
			exit 1
		fi
		slot1="[[:lower:]]+[[:alnum:]]*"
		slot2="[[:digit:]]{1,9}"
		slot3="$slot2"
		regex="^($slot1):($slot2):($slot3)\s*$"
		if [[ "$subuid" =~ $regex ]]; then
			subuid=${BASH_REMATCH[2]}
		else
			echo "Something is wrong with the output of max-subuid.sh: $subuid"
			exit 1
		fi

		subgid="`bash max-subuid.sh --user $lxcowner --subgid --show`"
		if [ "$?" -eq "1" ]; then
			echo "Cannot find subuid for the user. Exiting."
			exit 1
		fi
		if [[ "$subgid" =~ $regex ]]; then
			subgid=${BASH_REMATCH[2]}
		else
			echo "Something is wrong with the output of max-subuid.sh: $subgid"
			exit 1
		fi
	else
		echo "Cannot infer subuid for the user $lxcuser"
		exit 1
	fi

	logexec sudo touch $lxcpath/rootfs/var/lib/sudo/$lxcuser
	logexec sudo touch $lxcpath/rootfs/var/lib/sudo/$lxcuser/0
	if [ "$usermode" -eq "1" ]; then
		logexec sudo chown -R $subuid:$subgid $lxcpath/rootfs/var/lib/sudo/$lxcuser
	fi
	if ! sudo grep '!tty_tickets' $lxcpath/rootfs/etc/sudoers; then
		if [ ! -f "$lxcpath/rootfs/etc/sudoers.d/tty_tickets" ]; then
			$loglog
			echo 'Defaults         !tty_tickets' | sudo tee $lxcpath/rootfs/etc/sudoers.d/tty_tickets >/dev/null
			if [ "$usermode" -eq "1" ]; then
				logexec sudo chown 100000:100000 $lxcpath/rootfs/etc/sudoers.d/tty_tickets
			fi
		fi
	fi
fi

