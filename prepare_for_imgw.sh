#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Prepares the machine for compilation of the IMGW PROPOZE code


Usage:

$(basename $0) [--docs] [--help] [--debug] [--log <output file>]


where
 --docs                   - Prepares also all dependencies for building the documentation  
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands


Example2:

$(basename $0) --docs --debug
"


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
	--docs)
	flag_docs=1
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
	external_opts="--debug"
fi

install_apt_packages git cmake build-essential gfortran libboost-system1.58-dev libboost-program-options1.58-dev jq

install_apt_packages libboost-filesystem-dev libboost-system-dev libboost-log-dev libboost-date-time-dev libboost-thread-dev libboost-chrono-dev libboost-atomic-dev

if [ "$flag_docs" == "1" ]; then
	install_apt_packages mkdocs
fi
