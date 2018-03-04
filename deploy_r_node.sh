#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Deploys the R in the server on the given ssh address


Usage:

$(basename $0) <ssh addres of the server> [--rstudio] [--rstudio-server] [--user <user>]
             [--repo-server <repo-address>] [--deb-folder <path>]
             [--help] [--debug] [--log <output file>]  


where
 ssh addres of the server      - Address to the server, including username, e.g. root@134.234.3.63
 --debug                       - Flag that sets debugging mode. 
 --log                         - Path to the log file that will log all meaningful commands
 --repo-server <repo-address>  - repo-addres is an address of the repo server. Repo server might be also in the
                                 format smb://<samba-server>/<share>, in which case a samba client will be installed
                                 as well, and the samba share will be created that is mounted in the
                                 /mnt/r-repo
  --rstudio, --rstudio-server  - Whether to install this component
  --user <user>                - Name of the user that will have R installed. Defaults to \"auto\", which
                                 is user with name equal the first (alphabetically) subfolder of the /home
  --deb-folder <path>          - Folder where to keep the .deb files for the rstudio and rstudio-server.
                                 If auto and repo-server is smb share, it would default to the /debs folder
                                 inside the share.



Example2:

$(basename $0) root@109.74.199.59  --n2n-server 172.104.148.166:5535 --n2n-password szakal --debug

"

ssh_address=$1
if [ -z "$1" ]; then
	echo "$usage"
	exit 0
fi

username=$(whoami)
user=auto
deb_folder=auto



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
	--user)
	auto=$1
	shift
	;;
	--deb-folder)
	deb_folder=$1
	shift
	;;
	--repo-server)
	repo_server=$1
	shift
	;;
	--rstudio)
	opts2="$opts2 --rstudio"
	;;
	--rstudio-server)
	opts2="$opts2 --rstudio-server"
	;;
	-*)
	echo "Error: Unknown option: $1" >&2
	echo "$usage" >&2
	exit 1
	;;
esac
done

opts=""

if [ -n "$debug" ]; then
	opts="$opts --debug"
	if [ -z "$log" ]; then
		log=/dev/stdout
	else
		opts="$opts --log $log"
	fi
fi

parse_URI $ssh_address
if [ -z "$ip" ]; then
	errcho "You must provide a valid ssh address in the first argument"
	exit 1
fi

if [ "${user}" == "auto" ]; then
	user=$(lxc exec ls -1 /home | head -n 1)
fi

./prepare_remote_ubuntu.sh $ssh_address --wormhole $opts

if [ -n "${repo_server}" ]; then
	pattern='^smb://([^/]+)/([^/])(/(.*))$'
	if [[ "${repo_server}" =~ $pattern ]]; then
		smb_server=${BASH_REMATCH[1]}
		smb_share=${BASH_REMATCH[2]}
		smb_prefix=${BASH_REMATCH[3]}
		./execute-script-remotely.sh prepare_samba_client.sh --ssh-address $ssh_address  $opts -- ${smb_server} ${dmb_share} /mnt/r-repo  --user ${user} 
		opts2="${opts2} --repo-server file:///mnt/r-repo/${smb_prefix}"
		if [ "${deb_folder}" == "auto" ]; then
			deb_folder=/mnt/r-repo/debs
			opts2="${opts2}" --deb-folder ${deb_folder}
		fi
	else
		if [ "${deb_folder}" == "auto" ]; then
			deb_folder=
		fi
		opts2="${opts2} --repo-server ${repo_server}"
	fi
fi

./execute-script-remotely.sh prepare-R-node.sh --ssh-address $ssh_address  $opts -- $opts2 
