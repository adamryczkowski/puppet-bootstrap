#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Script that simply creates a empty file. 

Usage:

$(basename $0) --file <filename>

where

 --touch <filename>  - Name of the file to create
 --debug            - Flag that sets debugging mode. 
 --log              - Path to the log file that will log all meaningful commands


Example:

$(basename $0) --touch test.flag --debug
"

dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}
mypath=${0%/*}
mypath=`dir_resolve $mypath`
cd $mypath
debug=0


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
	--touch)
	filename="$1"
	shift
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
fi



if [ -z "$filename" ]; then
        errcho "You must specify file name with parameter --touch"
        echo "$usage" >&2
        exit 1
fi

if [ ! -f "${filename}" ]; then
        logexec touch "${filename}"
fi

