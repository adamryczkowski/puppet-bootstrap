#!/bin/bash
cd `dirname $0`
. ./common.sh


case $- in *x*) USE_X="-x";; *) USE_X=;; esac

#set +x

#echo "#@@@@@@#@@@@@@#@@@@@# $@ #@@@@@@#@@@@@@#@@@@@#"

function exitfunction()
{
	if [ -n "$remote_dir" ]; then
		if [ -d $remote_dir ]; then
			rm -r $remote_dir
		fi
	fi
	if [ -n "$full_remote_dir" ]; then
		if [ -d $full_remote_dir ]; then
			sudo rm -r $full_remote_dir
		fi
	fi
	if [ -n "$USE_X" ]; then
		set -x
	fi
	exit $1
}

trap 'exitfunction' EXIT


usage="
This script sends script to the remote machine either by lxc send or ssh.


Usage:

$(basename $0) <script path> [--ssh-address <host_address>]
[--lxc-name <lxcname>] [--user <user>]
[--debug] [--step-debug] [--extra-executable] [--use-repo]
-- <arguments that will get send to the remote script>

where

<script path>      - path to the script, to send. The script doesn't need to
have execution rights.
--ssh-address      - ssh address in format [user@]host[:port] to the remote
system. Port defaults to 22, and user to the current user.
--lxc-name         - name of the lxc container to send the command to.
The command will be transfered by and executed
by means of the lxc api.
--user             - name of the user, on behalf of which the script
will be run. The username defaults to the connected
user in case of ssh, and root in case of lxc.
			--step-debug       - Will run the target script with bash -x,
			the line debugging option.
			--repo-path        - Will use repo_path environment variable to use local file repository.
			Will temporarily mount the folder, when used with lxc,
			Do nothing when used locally
			And mount using sshfs when used remotely via ssh.
			--extra-executable - Extra file(s) that will be transfered to the remote host.
			Each instantion of this parameter will add another file.

			Example:

			$(basename $0) test.sh --ssh-address testnode -- file tmp.flag
			"


function errcho()
{
	>&2 echo $@
}

dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}
exec_mypath=${0%/*}
exec_mypath=`dir_resolve $exec_mypath`
cd $exec_mypath
exec_host=localhost

if [ "$1" == "--help" ]; then
	echo "$usage"
	exit 0
fi

exec_script=$1
if [ -z "$exec_script" ]; then
	echo "$usage"
	exit 0
fi
shift

if [ ! -f "$exec_script" ]; then
	errcho "Cannot find script at location $exec_script"
	exit 1
fi

#1 - localhost
#2 - by ssh on remote host.
#3 - lxc node
exec_mode=2
exec_fulldebug=0
debug=0
exec_lxcname=""
exec_opts=""
log=""
exec_user=""
use_repo=0
exec_debug=0
exec_port=22

collect_dependencies "$exec_script"

add_dependency "common.sh"
for plik in lib*.sh; do
  add_dependency "$plik"
done

while [[ $# > 0 ]]
do
exec_key="$1"
shift

case $exec_key in
	--debug|-x)
	exec_debug=1
	debug=1
	;;
	--extra-executable)
	add_dependency "$1"
	shift
	;;
	--ssh-address)
	ssh_address=$1
	shift
	;;
	--step-debug)
	exec_fulldebug=1
	;;
	--user)
	exec_user=$1
	shift
	;;
	--lxc-name)
	exec_lxcname=$1
	shift
	;;
	--repo-path)
	repo_path="$1"
	shift
	;;
	--)
	exec_opts="$*"
	shift $#
	;;
	--log)
	log=$1
	shift
	;;
	*)
	echo "Unkown parameter '$exec_key'. Aborting."
	exit 1
	;;
esac
done

if [ "$exec_fulldebug" -eq "1" ]; then
	set -x
fi
#set -x

if [ -n "$debug" ]; then
	if [ -z "$log" ]; then
		log=/dev/stdout
	fi
fi


if [ -z "${ssh_address}" ] && [ -z "${exec_lxcname}" ]; then
        errcho "You must provide either --ssh-address or --lxc-name argument."
        exit 1
fi

if [ -n "${ssh_address}" ] && [ -n "${exec_lxcname}" ]; then
        errcho "You must provide only one, either --ssh-address or --lxc-name argument."
        exit 1
fi

if [ -n "${ssh_address}" ]; then
        pattern='^(([[:alnum:]]+)://)?(([[:alnum:]]+)@)?([^:^@]+)(:([[:digit:]]+))?$'
        if [[ "$ssh_address" =~ $pattern ]]; then
                proto=${BASH_REMATCH[2]}
                sshuser=${BASH_REMATCH[4]}
                sshhost=${BASH_REMATCH[5]}
                exec_host="${sshhost}"
                sshport=${BASH_REMATCH[7]}
        else
                errcho "You must put proper address of the ssh server in the first argument, e.g. user@host.com:2022"
                exit 1
        fi
        if [ -z "$proto" ]; then
                proto='ssh'
        fi
        if [ -z "$sshuser" ]; then
                sshuser="$USER"
        fi
        if [ -z "$sshport" ]; then
                sshport='22'
        fi
        if [ "$proto" != 'ssh' ]; then
                errcho "You must connect using the ssh protocol, not $proto."
                exit 1
        fi
        if [ "$sshport" != "22" ]; then
	        exec_portarg1="-p $sshport"
	        exec_portarg2="-P $sshport"
        else
	        exec_portarg1=''
	        exec_portarg2=''
        fi
        exec_mode=2
else
        sshuser='root'
fi

if [ -z "$exec_user" ]; then
        if [ "$exec_mode" == "2" ]; then
                exec_user=$sshuser
        fi
        if [ "$exec_mode" == "3" ]; then
                exec_user=root
        fi
fi

if [ "$exec_host" == "localhost" ]; then
	exec_mode=1
fi

if [ "$exec_debug" -eq 1 ]; then
	exec_opts="$exec_opts --debug"
fi

if [ -n "$log" ]; then
	if [ "$exec_host" != "localhost" ]; then
		prefix="$exec_user@$exec_host"
	else
		if [ "$exec_user" == "$(whoami)" ]; then
			prefix=""
		else
			prefix="$exec_user@localhost"
		fi
	fi
	logatpreviousmsg "$prefix $exec_script $exec_opts"
fi

if [ -n "$exec_lxcname" ]; then
	if lxc info ${exec_lxcname}>/dev/null 2>/dev/null; then
		exec_sshhome=`getent passwd $(whoami) | awk -F: '{ print $6 }'`
		exec_lxcsudo=""
	else
		errcho "Cannot find lxc container with name $exec_lxcname"
		exit 1
	fi
	exec_mode=3
fi

case $exec_mode in
	1)
#localhost
	remote_dir=$(mktemp -d)
	rsync -avPR ${dependencies[@]} $tmpdir
	if [ "$exec_user" != "$(whoami)" ]; then
		exec_prefix="sudo -i -u ${exec_user} -- "
		sudo chown -R ${exec_user} $remote_dir
	else
		exec_prefix=""
	fi
	;;
	2)
#ssh
	if [ "${sshuser}" == "${exec_user}" ]; then
		exec_prefix="ssh ${exec_portarg1} $sshuser@$exec_host  -- "
	else
		exec_prefix="ssh ${exec_portarg1} $sshuser@$exec_host -- sudo -Hu $exec_user -- "
	fi
	remote_dir=$(ssh ${exec_portarg1} ${sshuser}@${exec_host} -- mktemp -d)
	rsync -avPR ${dependencies[@]} ${sshuser}@${exec_host}:${remote_dir}
	if [ "${sshuser}" != "${exec_user}" ]; then
		ssh ${exec_portarg1} ${sshuser}@${exec_host} -- chown -R ${exec_user} ${remote_dir}
	fi

	if [ "$use_repo" == "1" ]; then
		errcho "--use-repo not supported when calling via ssh."
#		if !ssh ${sshuser}@${exec_host} ${exec_portarg1} -- dpkg -s "$package">/dev/null  2> /dev/null; then
#			logexec ssh ${sshuser}@${exec_host} ${exec_portarg1} -- sudo apt-get --yes --force-yes -q  install sshfs
#		fi
		exit 1
	fi

	;;
	3)
#lxc
	remote_dir=$(lxc exec ${exec_lxcname} --mode=non-interactive -- mktemp -d)
	exec_prefix="lxc exec ${exec_lxcname} --mode=non-interactive -- "
	for plik in ${dependencies[@]}; do
		lxc exec ${exec_lxcname} --mode=non-interactive -- mkdir -p "$(dirname ${exec_lxcname}/${plik})"
		lxc file push ${plik} ${exec_lxcname}/${remote_dir}/${plik}
	done
	if [ "root" != "${exec_user}" ]; then
		${exec_prefix} chown -R ${exec_user} ${remote_dir}
	fi

	if [ ! "$repo_path" == "" ]; then
		if ! lxc config device list ${exec_lxcname} | grep tmprepo; then
			lxc exec ${exec_lxcname} --mode=non-interactive -- mkdir -p ${repo_path}
			lxc config device add ${exec_lxcname} tmprepo disk path="${repo_path}" source="${repo_path}"
		fi
	fi

	;;
esac







function appendlog ()
{
#Funkcja zbierająca log na końcu pracy
	if [ -n "$log" ] && [ "$log" != "/dev/stdout" ]; then
		case $exec_mode in
			1)
			cat $remote_dir/log.log >>$log
			;;
			2)
			#ssh
			ssh $sshuser@$exec_host cat $remote_dir/log.log >>$log
			;;
			3)
			#lxc
			lxc exec ${exec_lxcname} --mode=non-interactive -- cat $remote_dir/log.log >>$log
			if [ ! "$repo_path" == "" ]; then
				lxc config device remove ${exec_lxcname} tmprepo disk
			fi
			;;
			*)
			echo "Error. Aborting."
			exit 1
			;;
		esac
#		echo "########################### RETURN #############################" >>$log
#		echo >>$log
#		echo >>$log
	fi
}

#A teraz wykonujemy skrypt
if [ -n "$log" ] && [ "$log" != "/dev/stdout" ] ; then
	trap 'appendlog' ERR
#	logheading $exec_prefix $remote_dir $exec_opts
#	echo "$exec_prefix $remote_dir $exec_opts"
fi
if [ "$exec_fulldebug" -eq "1" ]; then
#	if [ "$exec_fulldebug" -eq "1" ]; then
#		echo "EXECUTING $exec_prefix bash -x -- $remote_dir $exec_opts"
#	fi
	$exec_prefix bash -x -- ${remote_dir}/${exec_script} $exec_opts
else
	$exec_prefix bash -- ${remote_dir}/${exec_script} $exec_opts
fi
exec_err=$?
trap 'errorhdl' ERR

appendlog

if [ $exec_err -ne 0 ]; then
	exit $exec_err
fi
