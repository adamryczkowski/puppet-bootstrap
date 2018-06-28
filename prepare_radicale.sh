#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Prepares the radicale calendar server


Usage:

$(basename $0)  [--cal_user <user>:<password>] 
                [--help] [--debug] [--log <output file>] 


where

 --debug                      - Flag that sets debugging mode. 
 --log                        - Path to the log file that will log all meaningful commands

Example2:

$(basename $0) --debug

"

if [ -z "$1" ]; then
	echo "$usage" >&2
	exit 0
fi

set -x

repo_server="http://cran.us.r-project.org"
deb_folder='/tmp'
install_lib=auto
rstudio_server=0
rstudio=0
user="$USER"

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
	--cal_user)
	cal_user=$1
	shift
	;;
	-*)
	echo "Error: Unknown option: $1" >&2
	echo "$usage" >&2
	exit 1
	;;
esac
done


install_apt_packages python3-pip apache2-utils git
install_pip3_packages radicale[bcrypt]

make_service_user radicale /var/lib/radicale/collections
make_sure_git_exists /var/lib/radicale/collections radicale

textfile /var/lib/radicale/collections/.git ".Radicale.cache
.Radicale.lock
.Radicale.tmp-*" radicale

textfile /etc/radicale/config "[auth]
type = htpasswd
htpasswd_filename = /etc/radicale/users
# encryption method used in the htpasswd file
htpasswd_encryption = bcrypt
# Average delay after failed login attempts in seconds
delay = 1

[server]
hosts = 0.0.0.0:5232
max_connections = 20
# 1 Megabyte
max_content_length = 10000000
# 10 seconds
timeout = 10

[storage]
filesystem_folder = /var/lib/radicale/collections
hook = git add -A && (git diff --cached --quiet || git commit -m \"Changes by \"%(user)s)
" radicale

if [ -n "$cal_user" ]; then
	pattern='^([^:]+):(.*)$'
	if [[ "$cal_user" =~ $pattern ]]; then
		cal_user=${BASH_REMATCH[1]}
		cal_password=${BASH_REMATCH[2]}
	else
		errcho "Wrong format of --cal_user argument. Please use \"user:pa\$\$word\"."
		exit 1
	fi
	
	if [ ! -f /etc/radicale/users ]; then
		infix=" -c "
	else
		infix=""
	fi 
	
	if ! grep -Exq "^${cal_user}:}" /etc/radicale/users; then
		logexec sudo htpasswd -B $infix -b /etc/radicale/users $cal_user $cal_password
	fi
fi

custom_systemd_service radicale "[Unit]
Description=A simple CalDAV (calendar) and CardDAV (contact) server
After=network.target
Requires=network.target

[Service]
ExecStart=/usr/bin/env python3 -m radicale
Restart=on-failure
User=radicale
# Deny other users access to the calendar data
UMask=0027
# Optional security settings
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
NoNewPrivileges=true
ReadWritePaths=/var/lib/radicale/collections

[Install]
WantedBy=multi-user.target
"

