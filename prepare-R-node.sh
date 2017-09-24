#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Prepares R in the server it is run on


Usage:

$(basename $0) [--help] [--debug] [--log <output file>]


where

 --ip                     - IP address in the private network of the node. 
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands


Example2:

$(basename $0) --debug

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
	-*)
	echo "Error: Unknown option: $1" >&2
	echo "$usage" >&2
	;;
esac
done

if [ -n "$debug" ]; then
	if [ -z "$log" ]; then
		log=/dev/stdout
	fi
	external_opts="--debug"
fi


if ! grep -q "^deb .*https://cran.rstudio.com" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
	$loglog
	echo "deb https://cran.rstudio.com/bin/linux/ubuntu xenial/" | sudo tee /etc/apt/sources.list.d/r.list
	
	logexec sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E084DAB9
	flag_need_apt_update=1
	install_apt_packages r-base r-cran-digest r-cran-foreign r-cran-getopt pandoc git-core r-cran-rcpp r-cran-rjava r-cran-rsqlite r-cran-rserve libxml2-dev libssl-dev libcurl4-openssl-dev
fi


