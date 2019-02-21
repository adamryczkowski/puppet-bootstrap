#!/bin/bash
#  ## dependency: prepare_ubuntu_user.sh

cd `dirname $0`
. ./common.sh

usage="
Installs synchronization with the given server. It assumes the server is already setup and the user can ssh to it without password.

Usage:

$(basename $0) --server <ip/dns_name of the server> --server-doc-root <root of the documents in server> 
               --local-doc-root <root of the local documents> [--unison-settings <relative path of the unison settings>]
               [--server-history-root <path of the history snapshots in the server>] [--user <username>]

where

 --server                 - Address of the server. Can be IP or DNS name.
 --server-doc-root        - Full path of the copy of the documents in the server. 
 --local-doc-root         - Full path of the local copy of the documents. Synchronization
                            strives to keep contents of this folder the same as --server-doc-root.
 --unison-settings        - Folder with the unison settings. This folder will be synchronized first.
                            Defaults to Unison
 --server-history-root    - Full path to the folder with history snapshots in the server. If not
                            specified, synchronization will not make history snapshot.
 --user <username>        - Name of the user for which context the synchronization will be run.
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands

Example:

$(basename $0) --server adam-990fx --server-doc-root /media/wielodysk/docs/Adam --local-doc-root /home/Adama-docs/Adam --server-history-root /media/wielodysk/docs/backups
"

dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}
mypath=${0%/*}
mypath=`dir_resolve $mypath`
cd $mypath

unison_settings_relpath=Unison
user=$USER

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--debug)
	debug=1
	;;
	--help)
        echo "$usage"
        exit 0
	;;
	--log)
	log=$1
	shift
	;;
	--server)
	server="$1"
	shift
	;;
	--server-doc-root)
	server_doc_root=$1
	shift
	;;
	--local-doc-root)
	local_doc_root=$1
	shift
	;;
	--unison-settings)
	unison_settings_relpath=$1
	shift
	;;
	--server-history-root)
	server_history_root=$1
	shift
	;;
	--user)
	user=$1
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

if [ -z $server ]; then
	errcho "--server cannot be empty"
	exit 1
fi

if [ -z $server_doc_root ]; then
	errcho "--server-doc-root cannot be empty"
	exit 1
fi

if [ -z $local_doc_root ]; then
	errcho "--local-doc-root cannot be empty"
	exit 1
fi

# 1. Install unison & unison-gtk

install_apt_packages unison unison-gtk

# 2. Make sure local docs exist
logmkdir "${local_doc_root}/${unison_settings_relpath}/do" $user

# 3. Make sure Unison roots contain minimum files
textfile ${homedir}/.unison/roots.prf "root = ${local_doc_root}
root = ssh://${server}/${server_doc_root}" $user
	
# 4. Upload standard unison bootstrap files
install_file files/unison/unison.prf "${local_doc_root}/${unison_settings_relpath}" $user
install_file files/unison/do/do-unison.prf "${local_doc_root}/${unison_settings_relpath}/do" $user
	
# 5. Upload synchronization script
install_script files/sync-local "/usr/local/bin" root
#TODO: dokończ skrypt sync-local. 
