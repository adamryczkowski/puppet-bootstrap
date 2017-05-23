#!/bin/bash

. ./common.sh

shopt -s extdebug

function doskip()
{
	file=${BASH_SOURCE[1]##*/}
	linenr=${BASH_LINENO[0]}
	line=`sed "1,$((${linenr}-1)) d;${linenr} s/^ *//; q" $file`
	if [ -f /tmp/tmp.txt ]; then
		rm /tmp/tmp.txt
	fi
	echo "$line" > /tmp/tmp2.txt
	mymsg=`msg2`
	exec 3>&1 4>&2 >>/tmp/tmp.txt 2>&1 
	set -x
	source /tmp/tmp2.txt
	exitstatus=$?
	set +x
	exec 1>&3 2>&4 4>&- 3>&-
	cat /tmp/tmp.txt
	return 1
}

trap "doskip" DEBUG

echo 1
echo 2
echo 3
echo 4
echo 5
echo 6
echo 7

exit


