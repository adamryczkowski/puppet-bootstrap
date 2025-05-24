#!/bin/bash
cd `dirname $0`
. ./common.sh

#To jest skrypt, który przygotowywuje gem z r10k


function dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}



mypath=${0%/*}
mypath=`dir_resolve $mypath`

gemrepo=/tmp/temp/gemrepo
mkdir -p $gemrepo 2>/dev/null
gem install r10k -i $gemrepo --no-rdoc --no-ri
if [ $? -ne 0 ]; then
	echo "Downloading gems failed!"
	exit 1
fi
mkdir $mypath/r10k-gems 2>/dev/null
rsync /tmp/temp/gemrepo/cache/*.gem $mypath/r10k-gems
