#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Prepares celery server with rabbitmq and redis and optionally flower.


Usage:

$(basename $0)  --use-flower
                [--help] [--debug] [--log <output file>] 


where
 --use-flower                 - Installs flower monitor

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

spack_location="$(get_home_dir ${USER})/tmp/spack"
spack_mirror=""
pre_install=()
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
	--spack-location)
	spack_location="$1"
	shift
	;;
	--spack-mirror)
	spack_mirror="$1"
	shift
	;;
	--pre-install)
	pre_install+=("$1")
	shift
	;;
	-*)
	echo "Error: Unknown option: $1" >&2
	echo "$usage" >&2
	exit 1
	;;
esac
done

add_apt_source_manual bintray.rabbitmq "deb https://dl.bintray.com/rabbitmq-erlang/debian $(get_ubuntu_codename) erlang
deb https://dl.bintray.com/rabbitmq/debian $(get_ubuntu_codename) main" https://github.com/rabbitmq/signing-keys/releases/download/2.0/rabbitmq-release-signing-key.asc rabbitmq.key

install_apt_packages rabbitmq-server


