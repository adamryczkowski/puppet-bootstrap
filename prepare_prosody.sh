#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Prepares the prosody XMPP IM server


Usage:

$(basename $0) <server_name> [--add-user <user>:<password>] 
                [--help] [--debug] [--log <output file>] 


where
 <server_name>                - Name of the server. All clients should identify the server by its name otherwise the certificate wouldn't work
 --ad-user <user>:<password>  - Adds user with on each run
 --debug                      - Flag that sets debugging mode. 
 --log                        - Path to the log file that will log all meaningful commands

Example2:

$(basename $0) --debug

"

if [ -z "$1" ]; then
	echo "$usage" >&2
	exit 0
fi

export server_name="$1"
shift

set -x

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
	--add-user)
	add_user_txt=$1
	shift
	;;
	-*)
	echo "Error: Unknown option: $1" >&2
	echo "$usage" >&2
	exit 1
	;;
esac
done

add_apt_source_manual prosody "deb https://packages.prosody.im/debian xenial main" "https://prosody.im/files/prosody-debian-packages.key" "prosody_Release.key"

install_apt_packages prosody

prosody_config=$(cat prosody.config.lua | envsubst)

textfile /etc/prosody/prosody.cfg.lua "$prosody_config" root
luac -p /etc/prosody/prosody.cfg.lua

if sudo [ ! -f /var/lib/prosody/${server_name}.crt ]; then
	echo "
PL

${server_name}



" | prosodyctl cert generate "${server_name}"
fi

if [ -n "$add_user_txt" ]; then
	pattern='^([^:]+):(.*)$'
	if [[ "$cal_user_txt" =~ $pattern ]]; then
		add_user=${BASH_REMATCH[1]}
		add_password=${BASH_REMATCH[2]}
	else
		errcho "Wrong format of --add_user argument. Please use \"user:pa\$\$word\"."
		exit 1
	fi
	logexec sudo prosodyctl adduser "${add_user}@${server_name}"
	echo "$add_password" | sudo prosodyctl passwd "${add_user}@${server_name}"
fi


