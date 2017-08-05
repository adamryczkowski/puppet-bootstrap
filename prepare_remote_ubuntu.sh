#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Launches 'prepare_ubuntu.sh' on remote node, using SSH root access.


Usage:

$(basename $0) [<username>@]ip address[:port]> [--ssh-username <ssh-username>] [--username <username>]
                     [--private-key-path <path to the private key>] 
                     [--external-key <string with external public key to access the account>]
                     [--help] [--debug] [--log <output file>] [--apt-proxy IP:PORT]


where

 <ip address[:port]>      - User name, IP Address (and port) of the external node. 
                            E.g. root@192.168.10.2:2022. 
                            Port defaults to 22, but username to current user. 
 --ssh-username <username>- Username of the exposed ssh root account of the remote host.
                            Defaults to 'root'.
 --username               - Name of the new username to set up. The new user will have sudo 
                            privillege without password, which should be revoked later. 
                            Defaults to the current username ($USER).
 --private_key_path       - Path to the file with the ssh private key. If set, installs private
                            key on the user's (--username) account in the container.
 --external-key <string>  - Sets external public key to access the account, 
                            both for (--ssh-username) and (--username).
 -p|--apt-proxy           - Address of the existing apt-cacher together with the port, e.g. 
                            192.168.1.1:3142
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands


Example:

$(basename $0) 192.168.10.2:2022 --apt-proxy 192.168.10.2:3142 --private-key-path ~/.ssh/id_rsa --username adam
"

dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}
mypath=${0%/*}
mypath=`dir_resolve $mypath`
cd $mypath

ssh_address=$1
if [ -z "$ssh_address" ]; then
	echo "$usage"
	exit 0
fi

shift

private_key_path=''
user=`whoami`
sshuser='root'


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
	-ssh-username)
	sshuser="$1"
	shift
	;;
	-u|--username)
	user="$1"
	shift
	;;
	--private-key-path)
	private_key_path="$1"
	shift
	;;
	--external_key)
	external_key="$1"
	shift
	;;
	--apt-proxy)
	aptproxy="$1"
	shift
	;;
        -*)
        echo "Error: Unknown option: $1" >&2
        echo "$usage" >&2
        ;;
esac
done

pattern='^(([[:alnum:]]+)://)?(([[:alnum:]]+)@)?([^:^@]+)(:([[:digit:]]+))?$'
if [[ "ssh_address" =~ $pattern ]]; then
        proto=${BASH_REMATCH[2]}
        sshuser=${BASH_REMATCH[4]}
        sshhost=${BASH_REMATCH[5]}
        sshport=${BASH_REMATCH[7]}
else
        errcho "You must put proper address of the ssh server in the first argument, e.g. user@host.com:2022"
        exit 1
fi
if [ -z '$proto' ]; then
        proto='ssh'
fi
if [ -z '$sshuser' ]; then
        sshuser='@USER'
fi
if [ -z '$sshport' ]; then
        sshport='22'
fi
if [ '$proto' != 'ssh' ]; then
        errcho "You must connect using the ssh protocol, not $proto."
        exit 1
fi

if [ -n "$debug" ]; then
	if [ -z "$log" ]; then
		log=/dev/stdout
	fi
fi



if ssh -o PasswordAuthentication=no ${sshuser}@${ssh_address} -p ${sshport} exit 2>/dev/null; then
        ssh-copy-id ${sshuser}@${ssh_address} -p ${sshport}
        
        if ! ssh -o PasswordAuthentication=no ${sshuser}@${ssh_address} -p ${sshport} exit 2>/dev/null; then
                errcho "Still cannot login to the remote host!" 
                exit 1
        fi  
fi



#if ! dpkg -s augeas-tools>/dev/null 2>/dev/null; then
#	logexec sudo apt-get --yes install augeas-tools
#fi

sudoprefix=""

hostlxcip=$(ifconfig $internalif  | grep 'inet addr:'| grep -v '127.0.0.1' | cut -d: -f2 | awk '{ print $1}')

if [ "$aptproxy" == "auto" ]; then
	if ! dpkg -s apt-cacher-ng>/dev/null 2>/dev/null; then
		logexec sudo apt-get --yes install apt-cacher-ng
	fi
	aptproxy="$hostlxcip:3142"
fi

#Ustawiamy fqdn i hostname...
#echo "Setting fqdn and hostname for the container and the host..."
echo "$lxcfqdn" | grep -Fq . 2>/dev/null
if [ $? -eq 0 ]; then
	lxcname=`echo $lxcfqdn | sed -En 's/^([^.]*)\.(.*)$/\1/p'` 
	hostsline="$lxcfqdn $lxcname" 
else
	lxcname=$lxcfqdn
	hostsline="$lxcname"
fi


#Jeśli kontenera nie ma, to go tworzymy
if $sudoprefix lxc info ${name}>/dev/null 2>/dev/null; then
	echo "container ${name} already installed!"
	while :
	do
		echo "(P)roceed or (A)bort?"
		read ans
		if [ "$ans" == "p" ] || [ "$ans" == "P" ]; then
			break
		else
			if [ "$ans" == "A" ] || [ "$ans" == "a" ]; then
				exit 1
			fi
		fi
	done
else
	logexec lxc init ubuntu:${release} ${name} 
#	logexec lxc stop ${name}
fi

if [ -n "${internalif}" ]; then
	logexec lxc network attach ${internalif} ${name} eth0
fi




#Ustawiamy wpis w hosts
if [ "$lxcip" != "auto" ]; then
	ifstate=$(lxc info ${name})
	pattern='^\s+eth0:\s+inet\s+([0-9./]*)'
	if [[ $ifstate =~ $pattern ]]; then
		actual_ip=${BASH_REMATCH[1]}
	fi

	staticleases=/etc/hosts
	if ! grep -q "^$lxcip $lxcname" $staticleases; then
		if grep -q "^$lxcip" $staticleases; then
			errcho "IP address $lxcip already reserved!"
			exit 1
		fi
		lxc config device set ${name} eth0 ipv4.address ${lxcip}

		if grep -q "^[\\s\\d\\.]+$lxcname" $staticleases; then
			#We need to replace the line rather than append
			if [ "$lxcname" == "$lxcfqdn" ]; then
				logexec sudo sed -i -e "/^[\\s\\d\\.]+$lxcname/$lxcip $lxcname/" $staticleases
			else
				logexec sudo sed -i -e "/^[\\s\\d\\.]+$lxcname/$lxcip $lxcname $lxcfqdn/" $staticleases
			fi
		else
			if [ "$lxcname" == "$lxcfqdn" ]; then
				$loglog
				echo "$lxcip $lxcname" | sudo tee -a $staticleases >/dev/null
			else
				$loglog
				echo "$lxcip $lxcname $lxcfqdn" | sudo tee -a $staticleases >/dev/null
			fi
		fi
		restartcontainer=1
	fi


#	tmpfile=$(mktemp)
#	$loglog
#	sudo grep -v ${lxcname} /var/lib/lxd/networks/${internalif}/dnsmasq.leases > ${tmpfile}
#	$loglog
#	cat ${tmpfile} | sudo tee /var/lib/lxd/networks/${internalif}/dnsmasq.leases 
#
#	if [ ! -d /etc/lxc ]; then
#		logexec sudo mkdir -p /etc/lxc
#	fi


#	staticleases=/etc/lxc/static_leases
#	staticleases=/var/lib/lxd/networks/${internalif}/dnsmasq.hosts
#	if [ ! -f $staticleases ]; then
#		logexec sudo touch $staticleases
#	fi
#
#	if ! grep -q "^$lxcname,$lxcip" $staticleases; then
#		if grep -q "$lxcip" $staticleases; then
#			errcho "IP address $lxcip already reserved!"
#			exit 1
#		fi
#		#lxc config device set ${name} eth0 ipv4.address ${lxcip}
#
#		if grep -q "^$lxcname,[\\s\\d\\.]+" $staticleases; then
#			#We need to replace the line rather than append
#			if [ "$lxcname" == "$lxcfqdn" ]; then
#				logexec sudo sed -i -e "/^$lxcname,[\\s\\d\\.]+/$lxcname,$lxcip/" $staticleases
#			fi
#		else
#			if [ "$lxcname" == "$lxcfqdn" ]; then
#				$loglog
#				echo "$lxcname,$lxcip" | sudo tee -a $staticleases >/dev/null
#			else
#				$loglog
#				echo "$lxcname,$lxcip" | sudo tee -a $staticleases >/dev/null
#			fi
#		fi
#		restartcontainer=1
#	fi
	logexec lxc config device set ${name} eth0 ipv4.address ${lxcip}

#	if [[ "$restartcontainer" == "1" ]]; then
#		if lxc config get ${name} volatile.last_state.power | grep -q -F "RUNNING"; then
#			logexec lxc stop ${name}
#		fi
#		logexec sudo service lxd restart
#	fi
#fi


#Zanim uruchomimy kontener, upewniamy się, że dostanie prawidłowy adres IP
#if [ "$lxcip" != "auto" ]; then
#	logexec sudo service lxd stop 
#
#	tmpfile=$(mktemp)
#	logexec sudo grep -v ${lxcname} /var/lib/lxd/networks/${internalif}/dnsmasq.leases > ${tmpfile}
#	cat ${tmpfile} | sudo tee /var/lib/lxd/networks/${internalif}/dnsmasq.leases 
#	logexec sudo service lxd start 
fi



#Upewniamy się, że kontener jest uruchomiony
if lxc config get ${name} volatile.last_state.power | grep -q -F "STOPPED" 2>/dev/null  ; then
	echo "Starting the container..."
	logexec $sudoprefix lxc start $name
fi

if [ -z $(lxc config get ${name} volatile.last_state.power) ] ; then
	echo "Starting the container..."
	logexec $sudoprefix lxc start $name
fi


	
if lxc config get ${name} volatile.last_state.power | grep -q -F "STOPPED"; then
	errcho "Failed to start lxc container $name!"
	exit 1
fi

#actual_ip=$(lxc info $name | grep -E "eth0:\sinet\s+" | grep -E -o "[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}")
echo "Waiting for the container to obtain ip address..."

while [ -z "${actual_ip}" ]
do
actual_ip=$(lxc exec $name -- ifconfig eth0 | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')
sleep 1
done
echo "Got IP address ${actual_ip}"


#Upewniamy się, że kontener ma prawidłwy hostname...
if ! lxc exec ${name} -- grep -q ${lxcname} /etc/hostname ; then
	$loglog 
	echo ${lxcname} | lxc exec $name -- tee /etc/hostname >/dev/null
fi

#...i prawidłowy wpis w /etc/hosts...
if lxc exec $name -- grep -q "^127\.0\.1\.1" /etc/hosts; then
	logexec lxc exec $name -- sed -i "s/^\(127\.0\.1\.1\s*\).*/\1$hostsline/" /etc/hosts
else
	$loglog 
	echo "127.0.1.1	$hostsline" | lxc exec $name -- tee -a /etc/hosts >/dev/null
fi


#Jeśli zachodzi potrzeba, to upewniamy się, że kontener dostał prawidłowy adres IP
if [ "$lxcip" != "auto" ]; then
	if [ "$actual_ip" != "$lxcip" ]; then
		errcho "Wrong IP address of $name. Restarting dnsmasq and emptying its cache, then restarting the container..."
		logexec lxc stop $name

		logexec sudo service lxd stop 

		tmpfile=$(mktemp)
#		$loglog
		logexec sudo grep -v ${lxcname} /var/lib/lxd/networks/${internalif}/dnsmasq.leases > ${tmpfile}
#		$loglog
		cat ${tmpfile} | sudo tee /var/lib/lxd/networks/${internalif}/dnsmasq.leases 

		logexec sudo service lxd start 

		logexec lxc start $name
		sleep 5
		actual_ip=$(lxc info $name | grep -E "eth0:\sinet\s+" | grep -E -o "[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}\.[[:digit:]]{1,3}")
		if [ "$actual_ip" != "$lxcip" ]; then
			errcho "Unable to set the IP address. It should be $lxcip, but the actual value is $actual_ip!"
			exit 5
		fi
	fi
fi



#Ustawiamy autostart...
#echo "Setting the autostart option..."
if [ "$autostart" == "YES" ]; then
	logexec lxc config set $name boot.autostart 1
else
	if [ "$autostart" == "NO" ]; then
		logexec lxc config set $name boot.autostart 0
	fi
fi


if [ -n "$aptproxy" ]; then
	$loglog
	echo "Acquire::http { Proxy \"http://$aptproxy\"; };" | lxc exec $name -- tee /etc/apt/apt.conf.d/90apt-cacher-ng >/dev/null
fi

# Creating user $lxcuser in the container
if [ "$lxcuser" != "ubuntu" ]; then
	logexec lxc exec $name -- adduser --quiet $lxcuser --disabled-password --gecos ""
	logexec lxc exec $name -- su -l $lxcuser -c "mkdir ~/.ssh"
	logexec lxc exec $name -- chmod 700 /home/$lxcuser/.ssh
fi

logexec lxc exec ${name} -- usermod -aG sudo  $lxcuser

if [ -f "$sshkey" ]; then
	mypubkey=$(cat $sshhome/.ssh/id_ed25519.pub)
	if ! lxc exec $name -- grep -q -F "$mypubkey" $sshhome/.ssh/authorized_keys 2>/dev/null; then
		$loglog
		cat $sshhome/.ssh/id_ed25519.pub | lxc exec $name -- su -l $lxcuser -c "tee --append ~/.ssh/authorized_keys" >/dev/null
	fi
fi


#echo "Adding the container to the hosts known_hosts file..."
if [ ! -d $sshhome/.ssh ]; then
	logexec mkdir $sshhome/.ssh
fi

if [ -f "$sshhome/.ssh/known_hosts" ]; then
	logexec ssh-keygen -f "$sshhome/.ssh/known_hosts" -R $name 2>/dev/null >/dev/null
	logexec ssh-keygen -f "$sshhome/.ssh/known_hosts" -R $lxcfqdn 2>/dev/null >/dev/null
	if [ -n "$actual_ip" ]; then
		logexec ssh-keygen -f "$sshhome/.ssh/known_hosts" -R $actual_ip 2>/dev/null >/dev/null
	fi
fi

$loglog 
ssh-keyscan -H $name >> $sshhome/.ssh/known_hosts 2>/dev/null
$loglog 
ssh-keyscan -H $lxcfqdn >> $sshhome/.ssh/known_hosts 2>/dev/null
if [ -n "$actual_ip" ]; then
	$loglog 
	ssh-keyscan -H $actual_ip >> $sshhome/.ssh/known_hosts 2>/dev/null
fi

#Echo Adding non-password sudo entry for our user
$loglog
echo "$lxcuser ALL=(ALL) NOPASSWD:ALL" | lxc exec $name -- tee /etc/sudoers.d/${lxcuser}_nopasswd 

#Updating, upgrading, installing simple stuff

logexec lxc exec $name -- apt update
logexec lxc exec $name -- apt --yes upgrade
logexec lxc exec $name -- apt install --yes liquidprompt byobu
logexec lxc exec $name -- liquidprompt_activate
logexec lxc exec $name -- su -l ${lxcuser} -c liquidprompt_activate
logexec lxc exec $name -- locale-gen en_US.UTF-8
logexec lxc exec $name -- locale-gen pl_PL.UTF-8

if [ -z $private_key_path ]; then
	logexec lxc exec $name -- su -l ${lxcuser} -c "ssh-keygen -t ed25519 -a 100 -f ~/.ssh/id_ed25519 -P ''"
else
	logexec lxc file push ${private_key_path} ${name}${sshhome}/.ssh/ >/dev/null
	logexec lxc exec ${name} -- chown ${lxcuser}:${lxcuser} ${sshhome}/.ssh/$(basename $private_key_path)
	logexec lxc exec ${name} -- chmod 0400 ${sshhome}/.ssh/$(basename $private_key_path)
	logexec echo "Installed the following ssh key:"
	logexec lxc exec ${name} -- ssh-keygen -lvf ${sshhome}/.ssh/$(basename $private_key_path)
fi









#To jest skrypt, który tworzy konter LXC z gitolite wewnątrz. Skrypt zakłada, że przynajmniej istnieje użytkownik puppet.
#install-gitolite-on-lxc.sh --fqdn <fqdn> --lxc-name <container name> [--lxc-username <lxc user name>] [---s|--git-source <URI to git repository with manifests]  [-g|--git-user <user name>] [-h|--git-user-keypath <keypath>] [--other-lxc-opts <other options to make-lxc-node>] 

#--other-lxc-opts - other options forwarded to make-lxc-node. Can be e.g. --ip <ip address>, --username <username> --usermode, --release <release name>, --autostart, --apt-proxy. The script will always set the following options: "--hostname $fqdn --username $lxcusername"
#--fqdn - fqdn
#--debug|-d
#--lxc-name - lxc container name 
#--lxc-username - lxc user name
#-g|--git-user - user name of the external user that will be given rights to access to container. By default it is the user that invokes this script
#-h|--git-user-keypath - sciezka do pliku z kluczem publicznym dla tego użytkownika. By default it is the public ssh key of the user that invokes this script


debug=0
alias errcho='>&2 echo'


dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}



mypath=${0%/*}
mypath=`dir_resolve $mypath`

usermode=0

if [ ! -d "$gemcache" ]; then
	gemcache=
fi

while [[ $# > 0 ]]
do
key="$1"
shift
case $key in
	-d|--debug)
	debug=1
	;;
	--fqdn)
	fqdn=$1
	shift
	;;
	--lxc-name)
	lxcname="$1"
	shift
	;;
	--lxc-username)
	lxcusername="$1"
	shift
	;;
	-g|--git-user)
	gituser="$1"
	shift
	;;
	--usermode)
	usermode=1
	;;
	-h|--git-user-keypath)
	gituserrsapath="$1"
	shift
	;;
	--other-lxc-opts|--)
	otherlxcoptions="$*"
	shift $#
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

if [ -z "$lxcname" ]; then
	errcho "You must specify --lxc-name parameter"
	exit 1
fi

if [ -z "$lxcusername" ]; then
	lxcusername=`whoami`
fi

if [ -n "$gituserrsapath" ]; then
	if [ -z "$gituser" ]; then
		errcho "Cannot use --git-user-keypath if no --git-user is specified."
		exit 1
	fi
fi

if [ -z "$gituser" ]; then
	gituser=`whoami`
fi

if [ -z "$gituserrsapath" ]; then
	sshhome=`getent passwd $gituser | awk -F: '{ print $6 }'`
	if [ $? -ne 0 ]; then
		errcho "Cannot automatically find public certificate for user $gituser."
		exit 1
	fi
	gituserrsapath=$sshhome/.ssh/id_rsa.pub
fi

if [ ! -f "$gituserrsapath" ]; then
	errcho "Cannot find public certificate for user $gituser in $gituserpath. You can create one with \'ssh-keygen -q -t rsa -N \"\" -f \"$gituserrsapath\""
	exit 1
fi

if [ -z "$fqdn" ]; then
	errcho "When creating lxc containers you MUST provide --fqdn option"
	exit 1
fi


opts="--hostname $fqdn --username $lxcusername --autostart $otherlxcoptions"
if [ "$usermode" -eq "1" ]; then
	opts="$opts --usermode"
fi
opts2="--host localhost --extra-executable force-sudo.sh"
if [ -n "$log" ]; then
	opts2="$opts2 --log $log"
fi
if [ "$debug" -eq "1" ]; then
	optx="-x"
else
	optx=""
fi
. ./execute-script-remotely.sh ./make-lxc-node.sh $optx $opts2 -- $lxcname $opts
exitstat=$?
if [ $exitstat -ne 0 ]; then
	exit $xitstat
fi



if [ -n "$gituser" ]; then
	remotekeypath=/tmp/$gituser.pub
	logexec scp $gituserrsapath $lxcusername@$fqdn:$remotekeypath 
	gitoliteopts="--other-user $gituser $remotekeypath"
fi
opts2="--user $lxcusername --host $fqdn"
if [ "$debug" -eq "1" ]; then
	opts2="$opts2 --debug"
fi
if [ -n "$log" ]; then
	opts2="$opts2 --log $log"
fi
. ./execute-script-remotely.sh remote/configure-gitolite.sh $opts2 -- $gitoliteopts

#scp $gituserrsapath $lxcusername@$fqdn:$remotekeypath >/dev/null
#scp remote/configure-gitolite.sh $lxcusername@$fqdn:/tmp >/dev/null
#ssh $lxcusername@$fqdn "chmod +x /tmp/configure-gitolite.sh"
#if [ "$debug" -eq "1" ]; then
#	ssh $lxcusername@$fqdn "bash -x -- /tmp/configure-gitolite.sh $gitoliteopts"
#else
#	ssh $lxcusername@$fqdn "/tmp/configure-gitolite.sh $gitoliteopts"
#fi
exitstat=$?
if [ $exitstat -ne 0 ]; then
	exit $exitstat
fi

#ssh $lxcusername@$fqdn "sudo adduser gitolite puppet"  >/dev/null
#exitstat=$?
#if [ $exitstat -ne 0 ]; then
#	exit $exitstat
#fi

