#!/bin/bash

## dependency: execute-script-remotely.sh
## dependency: prepare_ubuntu.sh

cd `dirname $0`
. ./common.sh


usage="
Launches 'prepare_ubuntu.sh' on remote node, using SSH root access.


Usage:

$(basename $0) [<username>@]ip address[:port]> [--username <username>]
[--private-key-path <path to the private key>]
[--external-key <string with external public key to access the account>]
[--help] [--debug] [--log <output file>] [--apt-proxy IP:PORT]


where

<ip address[:port]>      - User name, IP Address (and port) of the external node.
E.g. root@192.168.10.2:2022.
Port defaults to 22, but username to current user.
--username               - Name of the new username to set up. The new user will have sudo
privillege without password, which should be revoked later.
Defaults to the username used to connect to the server.
--private_key_path       - Path to the file with the ssh private key. If set, installs private
key on the user's (--username) account in the container.
--external-key <string>  - Sets external public key to access the account,
both for the account used for ssh access and
(--username). 'auto' means
public key of the calling user.
--wormhole               - Install magic-wormhole on the remote host
-p|--apt-proxy           - Address of the existing apt-cacher together with the port, e.g.
192.168.1.1:3142
--cli-improved           - Install all default command line tools.
--debug                  - Flag that sets debugging mode.
--log                    - Path to the log file that will log all meaningful commands


Example:

$(basename $0) 192.168.10.2:2022 --apt-proxy 192.168.10.2:3142 --private-key-path ~/.ssh/id_rsa --username adam
"

dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}
mypath=${0%/*}
mypath=`dir_resolve $mypath`
cd $mypath

ssh_address=$1
if [ -z "$ssh_address" ]; then
	echo "$usage"
	exit 0
fi

shift

private_key_path=''
user=`whoami`
sshuser='root'
install_cli_improved=0


while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--debug)
	debug=1
	;;
	--log)
	log=$1
	shift
	;;
	--help)
	echo "$usage"
	exit 0
	;;
	-u|--username)
	user="$1"
	shift
	;;
	--private-key-path)
	private_key_path="$1"
	shift
	;;
	--wormhole)
	flag_wormhole=1
	;;
	--external-key)
	external_key="$1"
	shift
	;;
	--cli-improved)
	install_cli_improved=1
	;;
	--apt-proxy)
	aptproxy="$1"
	shift
	;;
        -*)
        echo "Error: Unknown option: $1" >&2
        echo "$usage" >&2
        ;;
esac
done

pattern='^(([[:alnum:]]+)://)?(([[:alnum:]]+)@)?([^:^@]+)(:([[:digit:]]+))?$'
if [[ "$ssh_address" =~ $pattern ]]; then
        proto=${BASH_REMATCH[2]}
        sshuser=${BASH_REMATCH[4]}
        sshhost=${BASH_REMATCH[5]}
        sshport=${BASH_REMATCH[7]}
else
        errcho "You must put proper address of the ssh server in the first argument, e.g. user@host.com:2022"
        exit 1
fi
if [ -z "$proto" ]; then
        proto='ssh'
fi
if [ -z "$sshuser" ]; then
        sshuser="$USER"
fi
if [ -z "$sshport" ]; then
        sshport='22'
fi
if [ "$proto" != 'ssh' ]; then
        errcho "You must connect using the ssh protocol, not $proto."
        exit 1
fi

if [ -n "$debug" ]; then
	if [ -z "$log" ]; then
		log=/dev/stdout
	fi
	external_opts="--debug"
fi



if ! ssh -o PasswordAuthentication=no ${sshuser}@${sshhost} -p ${sshport} exit 2>/dev/null; then
        logexec ssh-copy-id ${sshuser}@${sshhost} -p ${sshport}

        if ! ssh -o PasswordAuthentication=no ${sshuser}@${sshhost} -p ${sshport} exit 2>/dev/null; then
                errcho "Still cannot login to the remote host!"
                exit 1
        fi
fi

if [ -n "$private_key_path" ]; then
        if [ ! -f "$private_key_path" ]; then
                errcho "Cannot find key in $private_key_path"
                exit 1
        fi
fi


external_opts2="--need-apt-update"
if [ -n "$aptproxy" ]; then
        external_opts2="--apt-proxy ${aptproxy}"
fi

if [ -n "$flag_wormhole" ]; then
	external_opts2="$external_opts2 --wormhole"
fi

if [ "${install_cli_improved}" == "1" ]; then
	external_opts2="$external_opts2 --cli-improved"
fi

./execute-script-remotely.sh prepare_ubuntu.sh ${external_opts} --ssh-address $ssh_address -- ${user} ${external_opts2}

external_opts2=""
if [ -n "$external_key" ]; then
        external_opts2="${external_opts2} --external-key '${external_key}'"
fi

if [ -n "$private_key_path" ]; then
        external_opts="${external_opts} --extra-executable '${private_key_path}'"
        external_opts2="${external_opts2} --private_key_path '$(basename ${private_key_path})'"
fi
if [ "$user" != "$sshuser" ]; then
        sshhome=$(getent passwd ${user} | awk -F: '{ print $6 }')
        public_key=$(cat ${sshhome}/.ssh/id_ed25519.pub)
        if [ -n "$public_key" ]; then
	        external_opts2="${external_opts2} --external-key \"${public_key}\""
	    fi
fi

./execute-script-remotely.sh prepare_ubuntu_user.sh ${external_opts} --ssh-address $ssh_address -- $user ${external_opts2}

if [ "$user" != "$sshuser" ]; then
        external_opts2=""
        if [ -n "$private_key_path" ]; then
                external_opts2="${external_opts2} --private_key_path '$(basename ${private_key_path})'"
        fi
        ./execute-script-remotely.sh prepare_ubuntu_user.sh ${external_opts} --ssh-address $ssh_address -- $sshuser ${external_opts2}
fi
