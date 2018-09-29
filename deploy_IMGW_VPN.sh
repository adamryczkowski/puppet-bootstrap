#!/bin/bash
## dependency: IMGW-VPN.sh

cd `dirname $0`
. ./common.sh


usage="
Prepares connection with the IMGW VPN


Usage:

$(basename $0)  <username>@<host> --password <password> 
		[--ssh <sshuser>@<sshhost>] [--lxc <container_name>]
		[--help] [--debug] [--log <output file>]


where
 <username>@<host>        - Username and the address of the VPN gateway
 --password               - Password for the VPN (in open text)
 --ssh-address            - ssh address in format [user@]host[:port] to the remote 
                            system. Port defaults to 22, and user to the current user.
 --lxc-name               - name of the lxc container to send the command to. 
                            The command will be transfered by and executed 
                            by means of the lxc api.
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands


Example2:

$(basename $0) https://aryczkowski@vpn.imgw.pl --password Qwer12345679 --debug
"

if [ -z "$1" ]; then
	echo "$usage"
	exit 0
fi
vpn_address=$1
shift

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
	--password)
	password=$1
	shift
	;;
	--ssh-address)
	ssh_address=$1
	shift
	;;
	--lxc-name)
	lxc_name=$1
	shift
	;;
	-*)
	echo "Error: Unknown option: $1" >&2
	echo "$usage" >&2
	exit 1
	;;
esac
done

if [ -n "$debug" ]; then
	if [ -z "$log" ]; then
		log=/dev/stdout
	fi
	external_opts="--debug --step-debug"
fi

if [ -z "$password" ]; then
	errcho "You must provide password"
	exit 1
fi

if [ -z "$ssh_address" ] &&[ -z "$lxc_name"]; then
	exec_prefix="--ssh-address ${USER}@localhost"
else
	if [ -n "$ssh_address" ]; then
		exec_prefix="--ssh-address ${ssh_address}"
	else
		exec_prefix="--lxc-name ${lxc_name}"
	fi
fi

./execute-script-remotely.sh IMGW-VPN.sh ${exec_prefix} $external_opts -- ${vpn_address} --password ${password}


