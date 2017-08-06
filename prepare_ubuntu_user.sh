#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Sets up a new user (if it doesn't exist) and sets some basic properties.
The script must be run as a root.



Usage:

$(basename $0) <user-name> [--private-key-path <path to the private key>] [--external-key <string with external public key to access the account>]
                        [--help] [--debug] [--log <output file>

where

 --private_key_path       - Path to the file with the ssh private key. 
                            If set, installs private key on the user's 
                            account in the container.
 --external-key <string>  - Sets external public key to access the account. It
                            populates authorized_keys
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands


Example:

$(basename $0) adam --private-key-path /tmp/id_rsa --external-key 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKw6Iu/QmWP0Qb5vHDK+dj7eFEPxhEl2x2JuE/t5D0PV adam@adam-gs40'
"

dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}
mypath=${0%/*}
mypath=`dir_resolve $mypath`
cd $mypath


user=$1
if [ -z "$user" ]; then
	echo "$usage"
	exit 0
fi

shift
debug=0


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
	--external-key)
	external_key="$1"
	shift
	;;
	--private_key_path)
	private_key_path=$1
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

if [ -n "$user" ]; then
        if ! grep -q "${user}:" /etc/passwd; then
                logexec sudo adduser --quiet $user --disabled-password --add_extra_groups --gecos ''
        fi
	sshhome=$(getent passwd $user | awk -F: '{ print $6 }')
        
        if ! groups $user | grep -q "sudo" ; then      
                logexec sudo usermod -a -G sudo $user
        fi
        if [ ! -d ${sshhome}/.ssh ]; then
                logexec sudo mkdir ${sshhome}/.ssh
                if [[ "$user" != "root" ]]; then
        		logexec sudo chown ${user}:${user} "$sshhome/.ssh"
		fi
        fi
        if [ -n "$external_key" ]; then
                if ! sudo [ -f ${sshhome}/.ssh/authorized_keys ]; then
                        loglog
                        echo "${external_key}" | sudo tee ${sshhome}/.ssh/authorized_keys
                        logexec sudo chmod 0600 ${sshhome}/.ssh/authorized_keys
                        logexec sudo chmod 0700 ${sshhome}/.ssh
                        if [[ "$user" != "root" ]]; then
                                logexec sudo chown ${user}:${user} -R ${sshhome}/.ssh 
		        fi
                else
                        if ! sudo grep -q "${external_key}" ${sshhome}/.ssh/authorized_keys; then
                                loglog
                                echo "${external_key}" >>${sshhome}/.ssh/authorized_keys
                        fi
                fi
        fi

        
        if ! sudo [ -f /etc/sudoers.d/${user}_nopasswd ]; then
                loglog
                echo "${user} ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/${user}_nopasswd
        fi
        
	if sudo [ ! -f "$sshhome/.ssh/id_ed25519.pub" ]; then
		if [ -f "$sshhome/.ssh/id_ed25519" ]; then
			errcho "Abnormal condition: private key is installed without the corresponding public key. Please make sure both files are present, or neither of them. Exiting."
			exit 1
		fi
		logexec sudo ssh-keygen -q -t ed25519 -N "" -a 100 -f "$sshhome/.ssh/id_ed25519"
		if [ $? -ne 0 ]; then
			exit 1
		fi
                if [[ "$user" != "root" ]]; then
        		logexec sudo chown ${user}:${user} "$sshhome/.ssh/id_ed25519"
        		logexec sudo chown ${user}:${user} "$sshhome/.ssh/id_ed25519.pub"
	        fi
	fi
	if dpkg -s liquidprompt >/dev/null 2>/dev/null; then
                if [[ "$user" != "root" ]]; then
                        logexec sudo -Hu $user liquidprompt_activate
                else
                        logexec liquidprompt_activate
                fi
        fi
fi



