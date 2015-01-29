#!/bin/bash
cd `dirname $0`

reset
eval "lxc-stop -n gitolite >/dev/null 2>/dev/null || true; lxc-destroy -n gitolite 2>/dev/null >/dev/null" &
eval "lxc-stop -n puppetmaster 2>/dev/null >/dev/null || true; lxc-destroy -n puppetmaster 2>/dev/null >/dev/null" &

wait
 
. ./common.sh

#To jest skrypt, który zajmuje się instalacją całego systemu puppet.
#Skrypt bierze na siebie odpowiedzialność za instalację puppeta (puppetdb, r10k i inni) wraz z gitolite oraz za konfigurację tego wszystkiego razem. 

#Jeśli poda się --gitolite-lxc-name lub --gitolite-lxc-name, to skrypt weźmie na siebie obowiązek stworzenia kontenera lxc gitolite/gitolite. Inaczej skrypt spróbuje skonfigurować istniejące kontenery korzystając z dostępu przez ssh i sudo - dlatego użytkownik musi upewnić się, że te istnieje dostęp ssh i uprawnienia sudo oraz jest gotowy na wpisywanie ew. haseł.

#syntax:
#bootstrap-puppet-and-friends.sh [--debug] [--gitolite-lxc-name <lxc name> [--gitolite-lxc-ip <ip>]] [--puppetmaster-lxc-name <lxc name> [--puppetmaster-lxc-ip <ip>]] --user-on-gitolite <username> --user-on-puppetmaster <username> --[lxc-host-ip <ip> --lxc-network <e.g. 10.0.17.0/24> --lxc-dhcprange <e.g. 10.0.17.200,10.0.17.254> [--lxc-usermode]]   [--apt-proxy <apt-proxy address>] [--import-puppet-manifest <git address> --dont-merge-manifest-with-template] [--import-git <reponame>:<git uri>
#--gitolite-lxc-name - Jeśli podane, to stworzony zostanie kontener lxc o nazwie <lxc name> zawierający gitolite.
#--gitolite-lxc-ip - Ma sens tylko, gdy podano --gitolite-lxc-name. Jeśli podane to, ustawia stały adres ip dla lxc gitolite
#--gitolite-lxc-name - Jeśli podane, to stworzony zostanie kontener lxc o nazwie <lxc name> zawierający gitolite.
#--gitolite-lxc-ip - Ma sens tylko, gdy podano --gitolite-lxc-name. Jeśli podane to, ustawia stały adres ip dla lxc gitolite
#--gitolite-name - Obowiązkowy argument. Nazwa komputera, w którym ma być gitolite. Można podać localhost.
#--gitolite-name - Obowiązkowy argument. Nazwa komputera, w którym ma być gitolite. Można podać localhost.
#--user-on-gitolite - Obowiązkowy argument. Nazwa użytkownika, pod którym będzie logowanie.
#--user-on-gitolite - Obowiązkowy argument. Nazwa użytkownika, pod którym będzie logowanie.
#--lxc-host-ip - Jeśli konfigurujemy sieć lxc, to tutaj definiujemy jej parametry.
#--lxc-network - np. 10.0.17.0/24. Jeśli konfigurujemy sieć lxc, to tutaj definiujemy jej parametry.
#--lxc-dhcprange - np. 10.0.17.200,10.0.17.254. Jeśli konfigurujemy sieć lxc, to tutaj definiujemy jej parametry.
#--lxc-usermode - Jeśli podane, to tworzone kontenery będą w trybie usermode. 
#--apt-proxy - Można podać: none, auto lub adres do istniejącego serwera apt-proxy. Jeśli podane zostanie auto, to localhost stanie się serwerem apt-proxy.
#--import-puppet-manifest - Jeśli podane, to główne repozytorium puppeta zostanie zaimportowane z tego adresu git. Domyślnie na początek historii git z zadanego repozytorium, chyba że podano --dont-merge-manifest-with-template.
#--dont-merge-manifest-with-template - Nie ma sensu, jeśli nie podano --import-puppet-manifest. Jeśli NIE podane, to na początek zaimportowanego repozytorium git z manifestem zostanie wstawiony pusty szablon konfiguracji.
#--import-git <reponame>:<git uri> - Jeśli do zadziałania manifestu puppet potrzeba jakiegoś zewnętrznego repozytorium, to tu można podać jego nazwę (np. puppet/autostart) i adres git dostępny dla gitolite.
# --debug
# --log - ścieżka do pliku, w którym są zapisywane faktycznie wykonywane komendy oraz ich output


alias errcho='>&2 echo'
dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}
mypath=${0%/*}
mypath=`dir_resolve $mypath`
cd $mypath

debug=0
gitolite_lxc=0
gitolite_lxc=0
lxc_usermode=0
dontmerge=0
uselxc=0

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--debug)
	debug=1
	;;
	--gitolite-lxc-name)
	gitolite_lxcname=$1
	gitolite_lxc=1
	uselxc=1
	shift
	;;
	--gitolite-lxc-ip)
	gitolite_ip=$1
	gitolite_lxc=1
	uselxc=1
	shift
	;;
	--puppetmaster-lxc-name)
	puppetmaster_lxcname=$1
	puppetmaster_lxc=1
	uselxc=1
	shift
	;;
	--puppetmaster-lxc-ip)
	puppetmaster_ip=$1
	puppetmaster_lxc=1
	uselxc=1
	shift
	;;
	--gitolite-name)
	gitolite_name=$1
	shift
	;;
	--puppetmaster-name)
	puppetmaster_name=$1
	shift
	;;
	--user-on-gitolite)
	gitolite_user=$1
	shift
	;;
	--user-on-puppetmaster)
	puppetmaster_user=$1
	shift
	;;
	--lxc-host-ip)
	lxc_hostip=$1
	uselxc=1
	shift
	;;
	--lxc-network)
	lxc_network=$1
	uselxc=1
	shift
	;;
	--lxc-dhcprange)
	lxc_dhcprange=$1
	uselxc=1
	shift
	;;
	--lxc-usermode)
	lxc_usermode=1
	uselxc=1
	;;
	--apt-proxy)
	aptproxy=$1
	shift
	;;
	--import-puppet-manifest)
	manifest_address=$1
	shift
	;;
	--dont-merge-manifest-with-template)
	dontmerge=1
	;;
	--import-git)
	import="$import $1"
	shift
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

if [ -n "$log" ]; then
	if [ -f $log ]; then
		rm $log
	fi
fi


#Najpierw apt-cache-ng
if [ -n "$aptproxy" ]; then
	opts="--apt-proxy $aptproxy"
	opts2="--host localhost"
	if [ -n "$log" ]; then
		opts2="$opts2 --log $log"
	fi
	if [ "$debug" -eq "1" ]; then
		optx="-x"
	else
		optx=""
	fi
	. ./execute-script-remotely.sh ./prepare-apt-cache.sh $optx $opts2 -- $opts 
fi
exitstat=$?
if [ $exitstat -ne 0 ]; then
	exit $exitstat
fi



#Algorytm:
#Jeśli potrzeba w ogóle lxc, to najpierw konfigurujemy lxc.
if [ "$uselxc" -eq "1" ]; then
	opts=
	if [ -n "$lxc_hostip" ]; then
		opts="$opts --hostip $lxc_hostip"
	fi
	if [ -n "$lxc_network" ]; then
		opts="$opts --network $lxc_network"
	fi
	if [ -n "$lxc_dhcprange" ]; then
		opts="$opts --dhcprange $lxc_dhcprange"
	fi
	if [ -n "$lxc_usermode" ]; then
		opts="$opts --usermode"
	fi
	opts2="--host localhost --extra-executable upstart-scripts/lxc-net.conf --extra-executable upstart-scripts/lxc-dnsmasq.conf"
	if [ -n "$log" ]; then
		opts2="$opts2 --log $log"
	fi
	if [ "$debug" -eq "1" ]; then
		optx="-x"
	else
		optx=""
	fi
	. ./execute-script-remotely.sh ./configure-lxc.sh $optx $opts2 -- $opts 
	exitstat=$?
	if [ $exitstat -ne 0 ]; then
		exit 1
	fi
fi


if [ "$puppetmaster_lxc" -eq "1" ]; then
	opts=
	if [ -n "$lxc_usermode" ]; then
		opts="$opts --usermode"
	fi
	if [ -n "$puppetmaster_name" ]; then
		opts="$opts --fqdn $puppetmaster_name"
	fi
	if [ -n "$puppetmaster_lxcname" ]; then
		opts="$opts --lxc-name $puppetmaster_lxcname"
	fi
	if [ -n "$puppetmaster_user" ]; then
		opts="$opts --lxc-username $puppetmaster_user"
	fi
	opts2="--autostart"
	if [ -n "$puppetmaster_ip" ]; then
		opts2="$opts2 --ip $puppetmaster_ip"
	fi
	if [ -n "$aptproxy" ]; then
		opts2="$opts2 --apt-proxy $aptproxy"
	fi
	opts3="--host localhost --extra-executable make-lxc-node.sh --extra-executable execute-script-remotely.sh --extra-executable remote/configure-puppetmaster.sh --extra-executable force-sudo.sh"
	if [ -n "$log" ]; then
		opts3="$opts3 --log $log"
		opts="$opts --log $log"
	fi
	if [ "$debug" -eq "1" ]; then
		optx="-x"
		opts="$opts --debug"
	else
		optx=""
	fi
	if [ -n "$opts2" ]; then
		. ./execute-script-remotely.sh ./install-puppetmaster-on-lxc.sh $optx $opts3 -- $opts --other-lxc-opts "$opts2"  
	else
		. ./execute-script-remotely.sh ./install-puppetmaster-on-lxc.sh $optx $opts3 -- $opts 
	fi
	exitstat=$?
	if [ $exitstat -ne 0 ]; then
		exit 1
	fi
fi

if [ "$gitolite_lxc" -eq "1" ]; then
	opts="--git-user `whoami`"
	if [ -n "$lxc_usermode" ]; then
		opts="$opts --usermode"
	fi
	if [ -n "$gitolite_name" ]; then
		opts="$opts --fqdn $gitolite_name"
	fi
	if [ -n "$gitolite_lxcname" ]; then
		opts="$opts --lxc-name $gitolite_lxcname"
	fi
	if [ -n "$gitolite_user" ]; then
		opts="$opts --lxc-username $gitolite_user"
	fi
	opts2="--autostart"
	if [ -n "$gitolite_ip" ]; then
		opts2="$opts2 --ip $gitolite_ip"
	fi
	if [ -n "$aptproxy" ]; then
		opts2="$opts2 --apt-proxy $aptproxy"
	fi
	opts3="--host localhost --extra-executable make-lxc-node.sh --extra-executable execute-script-remotely.sh --extra-executable remote/configure-gitolite.sh --extra-executable force-sudo.sh"
	if [ -n "$log" ]; then
		opts3="$opts3 --log $log"
		opts="$opts --log $log"
	fi
	if [ "$debug" -eq "1" ]; then
		optx="-x"
		opts="$opts --debug"
	else
		optx=""
	fi
	if [ -n "$opts2" ]; then
		. ./execute-script-remotely.sh ./install-gitolite-on-lxc.sh $optx $opts3 -- $opts --other-lxc-opts "$opts2"
	else
		. ./execute-script-remotely.sh ./install-gitolite-on-lxc.sh $optx $opts3 -- $opts
	fi
	exitstat=$?
	if [ $exitstat -ne 0 ]; then
		exit 1
	fi
fi


for entry in $import; do
	repo_name=`echo $entry | awk -F: '{ print $1 }'`
	repo_address=` echo ${entry:((${#repo_name}+1))}`
	opts="--ssh-address $gitolite_user@$gitolite_name --git-repo-uri $repo_address --reponame $repo_name -c `whoami`"
	opts2="--host localhost --extra-executable execute-script-remotely.sh --extra-executable remote/add-existing-repo.sh"
	if [ -n "$log" ]; then
		opts2="$opts2 --log $log"
	fi
	if [ "$debug" -eq "1" ]; then
		optx="-x"
	else
		optx=""
	fi
	. ./execute-script-remotely.sh ./import-into-gitolite.sh $optx $opts2 -- $opts 
	exitstat=$?
	if [ $exitstat -ne 0 ]; then
		exit 1
	fi
done

logexec sudo service lxc-dnsmasq restart

opts="--gitolite-server $gitolite_user@$gitolite_name --puppetmaster-server $puppetmaster_user@$puppetmaster_name"
if [ "$dontmerge" -eq "1" ]; then
	opts="$opts --dont-merge-existing-manifest-git"
fi
if [ -n "$manifest_address" ]; then
	opts="$opts --remote-manifest $manifest_address"
fi
if [ -n "$log" ]; then
	opts="$opts --log $log"
	logheading ./tie-gitolite-with-puppet.sh $opts 
fi
opts2="--host localhost --extra-executable execute-script-remotely.sh --extra-executable insert-repo-as-base-of-another.sh --extra-executable add-gitolite-user.sh --extra-executable remote/get-public-key.sh --extra-executable import-into-gitolite.sh --extra-executable remote/add-existing-repo.sh --extra-executable remote/tie-gitolite-on-puppetmaster.sh --extra-executable remote/tie-gitolite-on-gitolite.sh --extra-executable ensure-ssh-access-setup-by-proxies.sh --extra-executable remote/ensure-ssh-access-on-client.sh --extra-executable remote/ensure-ssh-access-on-server.sh"
if [ -n "$log" ]; then
	opts2="$opts2 --log $log"
fi
if [ "$debug" -eq "1" ]; then
	optx="-x"
else
	optx=""
fi
. ./execute-script-remotely.sh ./tie-gitolite-with-puppet.sh $optx $opts2 -- $opts 
exitstat=$?
if [ $exitstat -ne 0 ]; then
	exit 1
fi

opts="--puppetmaster $puppetmaster_name"
opts2="--user $gitolite_user --host $gitolite_name"
if [ -n "$gitolite_lxcname" ]; then
	opts2="$opts2 --lxc-name $gitolite_lxcname"
fi
if [ -n "$log" ]; then
	opts2="$opts2 --log $log"
fi
if [ "$debug" -eq "1" ]; then
	optx="-x"
else
	optx=""
fi
. ./execute-script-remotely.sh remote/configure-puppetclient.sh $optx $opts2 -- $opts 
exitstat=$?
if [ $exitstat -ne 0 ]; then
	exit 1
fi


opts="--puppetmaster $puppetmaster_name"
opts2="--user $puppetmaster_user --host $puppetmaster_name"
if [ -n "$puppetmaster_lxcname" ]; then
	opts2="$opts2 --lxc-name $puppetmaster_lxcname"
fi
if [ -n "$log" ]; then
	opts2="$opts2 --log $log"
fi
if [ "$debug" -eq "1" ]; then
	optx="-x"
else
	optx=""
fi
. ./execute-script-remotely.sh remote/configure-puppetclient.sh $optx $opts2 -- $opts 
exitstat=$?
if [ $exitstat -ne 0 ]; then
	exit 1
fi


opts="--puppetmaster $puppetmaster_name"
opts2="--host localhost"
if [ -n "$log" ]; then
	opts2="$opts2 --log $log"
fi
if [ "$debug" -eq "1" ]; then
	optx="-x"
else
	optx=""
fi
. ./execute-script-remotely.sh remote/configure-puppetclient.sh $optx $opts2 -- $opts 
exitstat=$?
if [ $exitstat -ne 0 ]; then
	exit 1
fi


logexec ssh $puppetmaster_user@$puppetmaster_name sudo puppet cert sign --all

logexec ssh $puppetmaster_user@$puppetmaster_name sudo puppet agent --test

logexec ssh $gitolite_user@$gitolite_name sudo puppet agent --test

logexec sudo puppet agent --test

lxc-attach -n $puppetmaster_lxcname -- puppet agent --test


