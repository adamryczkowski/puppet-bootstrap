#!/bin/bash
cd `dirname $0`

#Program jest częścią zdalną add-gitolite-user.sh
#Program zwraca ścieżkę lokalną do klucza publicznego zadanego użytkownika. Wywołujący go użytkownik musi mieć uprawnienia sudo.

#get-public-key.sh --username <username> [--create-key-if-missing] [--outfile <name of the output file>]

. ./common.sh

alias errcho='>&2 echo'


while [[ $# > 0 ]]
do
	key="$1"
	shift

	case $key in
		--create-key-if-missing)
			createkey=1
			;;
		--username)
			username=$1
			shift
			;;
		--outfile)
			outfile=$1
			shift
			;;
		--debug)
			debug=1
			;;
		--log)
			log=$1
			shift
			;;
		*)
			echo "Unkown parameter '$key'. Aborting."
			exit 1
			;;
	esac
done

if [ -z "$username" ]; then
	errcho "you must specify --username."
	exit 1
fi

sshhome=`getent passwd $username | awk -F: '{ print $6 }'`

if [ $? -ne 0 ]; then
	exit 1
fi
if [ -z "$sshhome" ]; then
	errcho "User $username seems not to exist on `hostname`"
	exit 1
fi

if [ -z "$outfile" ]; then
	outfile=`mktemp --suffix=.pub --dry-run`
fi

if sudo [ -f $sshhome/.ssh/id_rsa.pub ]; then
	logexec sudo cp $sshhome/.ssh/id_rsa.pub $outfile
else
	logexec sudo -u $username ssh-keygen -q -t rsa -N "" -f "$sshhome/.ssh/id_rsa"
	if [ $? -ne 0 ]; then
		exit 1
	fi
	logexec sudo cp $sshhome/.ssh/id_rsa.pub $outfile
	if [ $? -ne 0 ]; then
		exit 1
	fi
fi

sudo chown `whoami` $outfile

# echo outfile
