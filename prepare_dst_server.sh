#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Prepares Don't Starve Together dedicated server.


Usage:

$(basename $0)  [--cluster-token <token>]
                [--help] [--debug] [--log <output file>] 


where
 --cluster-token <token>      - Cluster token (defaults to 'gpMrs7hckCBAnHn2lAdcgEQFcbTigcxv')
 --debug                      - Flag that sets debugging mode. 
 --log                        - Path to the log file that will log all meaningful commands

Example2:

$(basename $0) --debug

"


#if [ -z "$1" ]; then
#	echo "$usage" >&2
#	exit 0
#fi

set -x

user="$USER"
cluster_token="gpMrs7hckCBAnHn2lAdcgEQFcbTigcxv"

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
	--cluster-token)
	cluster_token="$1"
	shift
	;;
	-*)
	echo "Error: Unknown option: $1" >&2
	echo "$usage" >&2
	exit 1
	;;
esac
done

if ! dpkg -s "steamcmd">/dev/null  2> /dev/null; then
	sudo dpkg --add-architecture i386

	sudo debconf-set-selections <<< 'steamcmd steam/license boolean true'
	sudo debconf-set-selections <<< 'steamcmd steam/question string I AGREE'

	add_apt_source_manual partner "deb http://archive.canonical.com/ubuntu $(get_ubuntu_codename) partner" 

	install_apt_packages steamcmd
fi

if [ ! -d /opt/dst ]; then
	logmkdir /opt/dst $USER
fi

steamcmd +login anonymous +force_install_dir /opt/dst +app_update 343050 validate +quit


