#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Enhances bare-bones Ubuntu installation with several tricks. 
The script must be run as a root.

It adds a new user,
fixes locale,
installs byobu, htop and mcedit



Usage:

$(basename $0) <user-name> [--private-key-path <path to the private key>] [--external-key <string with external public key to access the account>]
                        [--help] [--debug] [--log <output file>] [--apt-proxy IP:PORT]

where

 --private_key_path       - Path to the file with the ssh private key. If set, installs private
                            key on the user's account in the container.
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands


Example:

$(basename $0) mynode --release xenial --autostart --apt-proxy 192.168.10.2:3142 --private-key-path ~/.ssh/id_rsa
"

dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}
mypath=${0%/*}
mypath=`dir_resolve $mypath`
cd $mypath



name=$1
if [ -z "$name" ]; then
	echo "$usage"
	exit 0
fi

shift
autostart=NO
ssh=YES
release=`lsb_release -c | perl -pe 's/^Codename:\s*(.*)$/$1/'`
lxcip=auto
lxcfqdn=$name
private_key_path=''
common_debug=0
sshuser=`whoami`
lxcuser=`whoami`
hostuser=0


while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--debug)
	common_debug=1
	;;
	--external-key)
	external_key="$1"
	shift
	;;
	--username)
	sshuser=$1
	shift
	;;
	--private_key_path)
	private_key_path=$1
	shift
	;;
	--apt-proxy)
	aptproxy=$1
	shift
	;;
	--help)
        echo "$usage"
        exit 0
	;;
	--log)
	log=$1
	shift
	;;
        -*)
        echo "Error: Unknown option: $1" >&2
        echo "$usage" >&2
        ;;
esac
done

if [ -n "$common_debug" ]; then
	if [ -z "$log" ]; then
		log=/dev/stdout
	fi
fi
mkdir /root/.ssh

if [ ! -f /root/.ssh/authorized_keys ]; then
        if [ -n "$external_key" ]; then
                echo "${external_key}" >/root/.ssh/authorized_keys
        fi
        chmod 0600 /root/.ssh/authorized_keys
fi

if [ -n "$ssh_user"]; then
        adduser --quiet $ssh_user --disabled-password --add_extra_groups --gecos ''
        usermod -a -G sudo $ssh_user
        mkdir /home/adam/.ssh
        if [ ! -f /home/${ssh_user}/.ssh/authorized_keys ]; then
                if [ -n "$external_key" ]; then
                        echo "${external_key}" >/home/${ssh_user}/.ssh/authorized_keys
                fi
                chmod 0600 /home/${ssh_user}/.ssh/authorized_keys
                chmod 0700 /home/${ssh_user}/.ssh
                chown ${ssh_user}:${ssh_user} -R /home/${ssh_user}/.ssh 
        fi
        if [ ! -f /etc/sudoers.d/${ssh_user}_nopasswd ]
                echo "${ssh_user} ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/${ssh_user}_nopasswd
        fi
fi

if ! grep -q LC_ALL /etc/default/locale 2>/dev/null; then
tee /etc/default/locale <<EOF
LANG="en_US.UTF-8"
LC_ALL="en_US.UTF-8"
EOF
fi

if dpkg -s liquidprompt >/dev/null 2>/dev/null; then
        logexec apt install liquidprompt
        liquidprompt_activate
        if [ -n "$ssh_user"]; then
                su -l $ssh_user -c liquidprompt_activate
        fi
fi

if dpkg -s bash-completion >/dev/null 2>/dev/null; then
        logexec apt install bash-completion
fi

if dpkg -s htop >/dev/null 2>/dev/null; then
        logexec apt install htop
fi

if dpkg -s byobu >/dev/null 2>/dev/null; then
        logexec apt install byobu
fi
if dpkg -s mcedit >/dev/null 2>/dev/null; then
        logexec apt install mcedit
fi


if [ -n "$aptproxy" ]; then
	$loglog
	echo "Acquire::http { Proxy \"http://$aptproxy\"; };" | lxc exec $name -- tee /etc/apt/apt.conf.d/90apt-cacher-ng >/dev/null
fi





if [ -n "$sshuser" ]; then
	sshhome=`getent passwd $sshuser | awk -F: '{ print $6 }'`
	if [ ! -f "$sshhome/.ssh/id_ed25519.pub" ]; then
		if [ -f "$sshhome/.ssh/id_ed25519" ]; then
			errcho "Abnormal condition: private key is installed without the corresponding public key. Please make sure both files are present, or neither of them. Exiting."
			exit 1
		fi
		errcho "Warning: User on host does not have ssh keys generated. The script will generate them."
		logexec ssh-keygen -q -t ed25519 -N "" -a 100 -f "$sshhome/.ssh/id_ed25519"
		if [ $? -ne 0 ]; then
			exit 1
		fi
	fi
	sshkey=$sshhome/.ssh/id_ed25519.pub
fi



logexec apt update
logexec apt --yes upgrade
logexec locale-gen en_US.UTF-8
logexec locale-gen pl_PL.UTF-8

