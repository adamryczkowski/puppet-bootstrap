#!/bin/bash

## dependency: files/dont-starve-headless.sh
## dependency: files/update-dont-starve.sh


cd `dirname $0`
. ./common.sh


usage="
Prepares Don't Starve Together dedicated server.


Usage:

$(basename $0)  [--cluster-token <token>] [--cluster-name <name>] [--server-mod-collection <nr>]
                [--help] [--debug] [--log <output file>] 


where
 --cluster-token <token>      - Cluster token (defaults to 'gpMrs7hckCBAnHn2lAdcgEQFcbTigcxv')
 --cluster-name <name>        - Name of the clustre (defaults to WAM)
 --server-mod-collection <nr> - Steam number of the mod collection to install on server
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
cluster_name="WAM"
server_mod_collection="404903250"

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
	--cluster-name)
	cluster_name="$1"
	shift
	;;
	--server-mod-collection)
	server_mod_collection="$1"
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

if [ ! -f /opt/dst/bin/dontstarve_dedicated_server_nullrenderer ]; then
	logexec steamcmd +login anonymous +force_install_dir /opt/dst +app_update 343050 validate +quit
fi

home=$(get_home_dir ${USER})

install_apt_packages lib32gcc1 libcurl4-gnutls-dev:i386

install_script files/dont-starve-headless.sh ${home}
install_script files/update-dont-starve.sh ${home}

logmkdir "${home}/.klei/DoNotStarveTogether/${cluster_name}"

linetextfile ${home}/.klei/DoNotStarveTogether/${cluster_name}/dedicated_server_mods_setup.lua "ServerModCollectionSetup(\"${server_mod_collection}\")"

install_file files/dst_cluster.ini ${home}/.klei/DoNotStarveTogether/${cluster_name}/cluster.ini
