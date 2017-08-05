#!/bin/bash
cd `dirname $0`
. ./common.sh


case $- in *x*) USE_X="-x";; *) USE_X=;; esac

set +x

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
               [--lxc-name <lxcname>] [--username <user>] 
               [--debug] [--step-debug] [--extra-executable] 
               -- <arguments that will get send to the remote script>
               
where

 <script path>      - path to the script, to send. The script doesn't need to 
                      have execution rights.
 --ssh-address      - ssh address in format [user@]host[:port] to the remote 
                      system. Port defaults to 22, and user to the current user.
 --lxc-name         - name of the lxc container to send the command to. 
                      The command will be transfered by and executed 
                      by means of the lxc api.
 --username         - name of the user, on behalf of which the script 
                      will be run. The username defaults to the connected 
                      user in case of ssh, and root in case of lxc.
 --step-debug       - Will run the target script with bash -x, 
                      the line debugging option.
 --extra-executable - Extra file(s) that will be transfered to the remote host. 
                      Each instantion of this parameter will add another file. 

Example:

$(basename $0) test.sh --ssh_address testnode -- file tmp.flag
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

exec_script=$1
if [ -z "$exec_script" ]; then
	echo "$usage"
	exit 0
fi
shift

exec_extrascripts="$exec_script common.sh"

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
exec_debug=0
exec_port=22


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
	exec_extrascripts="$exec_extrascripts $1"
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

#if [ "$exec_fulldebug" -eq "1" ]; then
#	set -x
#fi
set -x

if [ -n "$debug" ]; then
	if [ -z "$log" ]; then
		log=/dev/stdout
	fi
fi


if [ -z "${ssh_address}" ] && [ -z "${lxc_name}" ]; then
        errcho "You must provide either --ssh-address or --lxc-name argument."
        exit 1
fi

if [ -n "${ssh_address}" ] && [ -n "${lxc_name}" ]; then
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

#Teraz kopiujemy skrypt i nadajemy mu uprawnienia
case $exec_mode in
	1)
#localhost
	exec_prefix=""
	exec_remote_dir="`mktemp -d`"
	exec_remote_path="$exec_remote_dir/`basename $exec_script`"
	for exec_file in $exec_extrascripts; do
		if [ "$exec_file" == "$exec_script" ]; then
			exec_rpath=$exec_remote_path
		else
			exec_rpath=$exec_remote_dir/$exec_file
			if [ ! -d "`dirname $exec_rpath`" ]; then
				mkdir -p `dirname $exec_rpath`
			fi
		fi
		cp $exec_file $exec_rpath
	done
	if [ -n "$log" ]; then
		#echo "Script $exec_script on `hostname`: ">$exec_remote_dir/log.log
		if [ "$log" == "/dev/stdout" ]; then
			exec_opts="$exec_opts --log /dev/stdout"
			if [ -n "$exec_user" ]; then
				pushd /dev >/dev/null
				exec_prevlink="$log"
				exec_link="$log"
				while exec_nextlink=$(readlink $exec_link); do
					exec_prevlink="$exec_link"
					exec_link="$exec_nextlink"
				done
				sudo chmod 777 $exec_prevlink
				popd >/dev/null
			fi
		else
			exec_opts="$exec_opts --log $exec_remote_dir/log.log"
		fi
	fi
	if [ "$exec_user" != "`whoami`" ]; then
		sudo chown -R $exec_user $exec_remote_dir
	fi
	sudo chmod -R +x $exec_remote_dir
	if [ "$exec_user" != "`whoami`" ]; then
		exec_prefix="sudo -i -u $exec_user --"
	else
		exec_prefix=""
	fi
	;;
	2)
#ssh
	exec_remote_dir=`ssh ${sshuser}@${exec_host} ${exec_portarg1} mktemp -d`
	exec_remote_path="$exec_remote_dir/`basename $exec_script`"
	for exec_file in $exec_extrascripts; do
		if [ "$exec_file" == "$exec_script" ]; then
			exec_rpath=$exec_remote_path
		else
			exec_rpath=$exec_remote_dir/$exec_file
			exec_command="if [ ! -d "`dirname $exec_rpath`" ]; then mkdir -p `dirname $exec_rpath`; fi"
			logexec ssh $exec_portarg1 $sshuser@$exec_host $exec_command
		fi
		logexec scp $exec_portarg2 $exec_file $sshuser@$exec_host:$exec_rpath >/dev/null
	done
	if [ -n "$log" ]; then
		#ssh $exec_user@$exec_host "echo \"Script $exec_script on \$(hostname): \" >$exec_remote_dir/log.log"
		if [ "$log" == "/dev/stdout" ]; then
			exec_opts="$exec_opts --log /dev/stdout"
		else
			exec_opts="$exec_opts --log $exec_remote_dir/log.log"
		fi
	fi
	if [ "$exec_user" != "$sshuser" ]; then
		if ! ssh $exec_portarg1 $sshuser@$exec_host sudo chown -R $exec_user $exec_remote_dir; then
        		if ! ssh $exec_portarg1 $sshuser@$exec_host chown -R $exec_user $exec_remote_dir; then
        		        errcho "Warning: insufficient privileges to change ownership of the file"
        		fi
                fi
	fi
	logexec ssh $exec_portarg1 $sshuser@$exec_host chmod -R +x $exec_remote_dir
	logexec ssh $exec_portarg1 $sshuser@$exec_host chmod +x $exec_remote_path
	exec_prefix="ssh $exec_portarg1 $sshuser@$exec_host -- sudo -Hu $exec_user -- "
	;;
	3)
#lxc
TODODOTODODOTODO
	exec_full_remote_dir=`mktemp --suffix=.ssh -d --tmpdir=$exec_lxcprefix/var/tmp`
	exec_full_remote_path="$exec_full_remote_dir/`basename $exec_script`"
	exec_uid=`grep $exec_user $exec_lxcprefix/etc/passwd | awk -F: '{ print $3 }'`
	for exec_file in $exec_extrascripts; do
		if [ "$exec_file" == "$exec_script" ]; then
			exec_rpath=$exec_full_remote_path
		else
			exec_rpath=$exec_full_remote_dir/$exec_file
			if [ ! -d "`dirname $exec_rpath`" ]; then
				mkdir -p `dirname $exec_rpath`
			fi
		fi
		cp $exec_file $exec_rpath
	done
	exec_remote_path=/`python -c "import os.path; print os.path.relpath('$exec_full_remote_path', '$exec_lxcprefix')"`
	exec_remote_dir=/`python -c "import os.path; print os.path.relpath('$exec_full_remote_dir', '$exec_lxcprefix')"`
	if [ -n "$log" ]; then
		#echo "Script $exec_script on `hostname`: ">>$exec_full_remote_dir/log.log
		#echo >>$exec_full_remote_dir/log.log
		if [ "$log" == "/dev/stdout" ]; then
			exec_opts="$exec_opts --log /dev/stdout"
		else
			exec_opts="$exec_opts --log $exec_remote_dir/log.log"
		fi
	fi
	sudo chown -R 10$exec_uid:10$exec_uid $exec_full_remote_dir
	sudo chmod -R +x $exec_full_remote_dir
	if [ $? -ne 0 ]; then
		errcho "Cannot find uid of the user $exec_user"
		exit 1
	fi
	exec_prefix="$exec_lxcsudo lxc-attach -n $exec_lxcname -- sudo -i -u $exec_user --"
	exec_postfix=""
	;;
	*)
	echo "Error. Aborting."
	exit 1
	;;
esac



function appendlog ()
{
#Funkcja zbierająca log na końcu pracy
	if [ -n "$log" ] && [ "$log" != "/dev/stdout" ]; then
		case $exec_mode in
			1)
			cat $exec_remote_dir/log.log >>$log
			;;
			2)
			#ssh
			exec_locallog=`mktemp --dry-run --suffix .log`
			scp $sshuser@$exec_host:$exec_remote_dir/log.log $exec_locallog >/dev/null
			cat $exec_locallog >>$log
			rm $exec_locallog
			;;
			3)
			#lxc
			sudo cat $exec_full_remote_dir/log.log >>$log
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
#	logheading $exec_prefix $exec_remote_path $exec_opts
#	echo "$exec_prefix $exec_remote_path $exec_opts"
fi
if [ "$exec_fulldebug" -eq "1" ]; then
#	if [ "$exec_fulldebug" -eq "1" ]; then
#		echo "EXECUTING $exec_prefix bash -x -- $exec_remote_path $exec_opts"
#	fi
	$exec_prefix bash -x -- $exec_remote_path $exec_opts
else
	$exec_prefix bash -- $exec_remote_path $exec_opts
fi
exec_err=$?
trap 'errorhdl' ERR

appendlog

if [ $exec_err -ne 0 ]; then
	exit $exec_err
fi

