#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Enhances bare-bones Ubuntu installation with several tricks. 
It adds a new user,
fixes locale,
installs byobu, htop and mcedit

The script must be run as a root.




Usage:

$(basename $0) <user-name> [--apt-proxy IP:PORT] 

where

 -p|--apt-proxy           - Address of the existing apt-cacher with port, e.g. 192.168.1.0:3142.
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands


Example:

$(basename $0) --apt-proxy 192.168.10.2:3142
"

dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}
mypath=${0%/*}
mypath=`dir_resolve $mypath`
cd $mypath


debug=0


while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--debug)
	debug=1
	;;
	--help)
        echo "$usage"
        exit 0
	;;
	--log)
	log=$1
	shift
	;;
	--apt-proxy)
	aptproxy=$1
	shift
	;;
        -*)
        echo "Error: Unknown option: $1" >&2
        echo "$usage" >&2
        ;;
esac
done

done_apt_update=0

if [ -n "$debug" ]; then
	if [ -z "$log" ]; then
		log=/dev/stdout
	fi
fi

if ! sudo -n true 2>/dev/null; then
        errcho "User $USER doesn't have admin rights"
        exit 1
fi

if [ -n "$aptproxy" ]; then
	$loglog
	echo "Acquire::http { Proxy \"http://$aptproxy\"; };" | sudo tee /etc/apt/apt.conf.d/90apt-cacher-ng >/dev/null
        logexec sudo apt update
        done_apt_update=1
        logexec sudo apt --yes upgrade
fi


if ! grep -q LC_ALL /etc/default/locale 2>/dev/null; then
sudo tee /etc/default/locale <<EOF
LANG="en_US.UTF-8"
LC_ALL="en_US.UTF-8"
EOF
logexec sudo locale-gen en_US.UTF-8
logexec sudo locale-gen pl_PL.UTF-8
fi

if ! dpkg -s liquidprompt >/dev/null 2>/dev/null; then
        if [ "$done_apt_update" == "0" ]; then
                logexec sudo apt update
                done_apt_update=1
        fi
        logexec sudo apt install --yes liquidprompt
fi
liquidprompt_activate

if ! dpkg -s bash-completion >/dev/null 2>/dev/null; then
        if [ "$done_apt_update" == "0" ]; then
                logexec sudo apt update
                done_apt_update=1
        fi
        logexec sudo apt install --yes bash-completion
fi

if ! dpkg -s htop >/dev/null 2>/dev/null; then
        if [ "$done_apt_update" == "0" ]; then
                logexec sudo apt update
                done_apt_update=1
        fi
        logexec sudo apt install --yes htop
fi

if ! dpkg -s byobu >/dev/null 2>/dev/null; then
        if [ "$done_apt_update" == "0" ]; then
                logexec sudo apt update
                done_apt_update=1
        fi
        logexec sudo apt install --yes byobu
fi

if ! dpkg -s mc >/dev/null 2>/dev/null; then
        if [ "$done_apt_update" == "0" ]; then
                logexec sudo apt update
                done_apt_update=1
        fi
        logexec sudo apt install --yes mc
fi



