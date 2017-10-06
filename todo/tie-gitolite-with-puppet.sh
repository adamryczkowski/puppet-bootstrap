#!/bin/bash
cd `dirname $0`
. ./common.sh

#Program służy do łączenia zaimportowanego do gitolite głównego repozytorium puppet z puppet. Skrypt zakłada, że puppet został skonfigurowany poprzez configure-puppetmaster.sh, tj. wykorzystuje repozytorium /srv/puppet.git. Skrypt ustawia wszystkie uprawnienia i konfiguruje git hook tak, że push do repozytorium gitolite jednocześnie robi push do repozytorium w puppecie (nie wykonywane jest puppet agent --test, bo przecież puppet może konfigurować wiele hostów)
#Skrypt zakłada, że użytkownik, który go wywołuje ma prawo modyfikować repozytorium gitolite-admin.
#Program wymaga, aby wcześniej zostały zaimportowane wszystkie kontrolowane przez nas repozytoria git z modułami (inaczej pierwsze deploy się nie uda) i głównym manifestem.
#Program wykonuje większość pracy na serwerze gitolite. Jeśli serwer puppet jest ten sam co gitolite, to skrypt również dostosuje git hook w lokalnej instalacji puppet.

#tie-gitolite-with-puppet 
#	-g|--gitolite-server <[username]@severname> SSH URI do serwera gitolite. Obowiązkowy parametr> 
#	--puppetmaster-is-local-to-gitolite 
#	--puppetmaster-server <[username]@servername SSH URI do serwera, jeśli puppetmaster jest oddzielny. Podania tego parametru zakłada, że puppetmaster nie jest lokalny. Użytkownik wywołujący skrypt musi mieć uprawnienia sudo do tego serwera w celu ustawienia kluczy> 
#       --puppetmaster-puppet-user - nazwa użytkownika na puppetmasterze, który ma prawo do deploy. Domyślnie "puppet"
#	-r|--main-manifest-repository <nazwa głównego repozytorium, domyślnie "puppet/manifest">
#	--dont-merge-existing-manifest-git - jeśli podane, to manifest w gitolite nie będzie połączony z istniejącym manifestem szkieletowym stworzonym automatycznie przez skrypt configure-puppetmaser.sh. Wtedy szkieletowe repozytorium zostanie zastąpione naszym
#	--puppetmaster-rsa-pub <ścieżka do klucza publicznego puppetmastera, osiągalna przez scp. Jeśli nie jest podana, to skrypt zaloguje się na puppetmasterze i uruchomi ssh-keygen>
#	--remote-manifest <akceptowalna przez git ścieżka do głównego repozytorium> - jeśli nie podane, to zostanie wykorzystane automatyczne, szkieletowe repozytorium


#
#Skrypt wykonuje następujące zadania:
#1. Dodaje do gitolite skrypt, który zostanie wywołany po każdym push do repozytorium --main-manifest-repository (Zadanie dla głównego skryptu oraz dla gitolite)
#2. Upewnia się, że puppet@puppetmaster ma prawo do pobierania repozytoriów puppet/* z gitolite (główny skrypt)
#3. Tworzy repozytorium manifest.git i importuje go do gitolite. Jest kilka sposobów tworzenia tego repozytorium, w zależności od --dont-merge-existing-manifest-git i tego, czy podano --remote-manifest:
#   a) --dont-merge-existing-manifest-git oraz nie podano remote-manifest -> skrypt wklei do gitolite szkieletowe repozytorium. TRYB "SKELETON"
#   b) brak --dont-merge-existing-manifest-git oraz nie podano remote-manifest -> Cannot merge when there is nothing to merge. Skrypt wykona się tak, jakby podano --dont-merge-existing-manifest-git
#   c) --dont-merge-existing-manifest-git oraz PODANO remote-manifest -> skrypt wstawi podane repozytorium do puppeta oraz wklei je do gitolite. Tryb "REPLACE"
#   c) brak --dont-merge-existing-manifest-git oraz PODANO remote-manifest -> skrypt dokona rebase podanego repozytorium tak, aby zawierało ono nasze szkieletowe repozytorium jako bazę. Tryb "REBASE"
#    
#4. 

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


domerge=1
puppetrepo=puppet/manifest
puppetsource="/srv/puppet.git"
puppetuser=puppet
puppetrsa=""

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--debug)
	debug=1
	;;
	-g|--gitolite-server)
	gitoliteserver=$1
	shift
	;;	
	--puppetmaster-is-local-to-gitolite)
	if [ -n "$puppetislocal" ]; then
		errcho "Cannot give --puppetmaster-is-local-to-gitolite AND -g|--gitolite-server parameters together"
		exit 1
	fi
	puppetislocal=1
	;;
	--puppetmaster-uri)
	puppetsource=$1
	shift
	;;
	--puppetmaster-server)
	if [ -n "$puppetislocal" ]; then
		errcho "Cannot give --puppetmaster-is-local-to-gitolite AND -g|--gitolite-server parameters together"
		exit 1
	fi
	puppetislocal=0
	puppetserver=$1
	shift
	;;
	--puppetmaster-puppet-user)
	puppetuser=$1
	shift
	;;
	--puppetmaster-rsa-pub)
	puppetrsa=$1
	shift
	;;
	--dont-merge-existing-manifest-git)
	domerge=0
	;;
	-r|--main-manifest-repository)
	puppetrepo=$1
	shift
	;;
	--remote-manifest)
	remoterepo=$1
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

mydir=`pwd`

if [ -z "$puppetislocal" ]; then
	ssh $gitoliteserver "ls /srv/puppet.git" 2>/dev/null >/dev/null
	if [ $? -ne 0 ]; then
		puppetislocal=0
	else
		puppetislocal=1
	fi
fi


#1. Dodaje do gitolite skrypt, który zostanie wywołany po każdym push do repozytorium --main-manifest-repository (Zadanie dla głównego skryptu oraz dla gitolite)
#2. Upewnia się, że puppet@puppetmaster ma prawo do pobierania repozytoriów puppet/* (główny skrypt)
#3. Tworzy repozytorium manifest.git i importuje je do gitolite. Jest kilka sposobów tworzenia tego repozytorium, w zależności od --dont-merge-existing-manifest-git i tego, czy podano --remote-manifest.


if [ "$puppetislocal" -eq "1" ]; then
	puppetserver=$gitoliteserver
fi

if [ -z "$puppetserver" ]; then
	errcho "When puppetmaster is not local to gitolite, you must specify address of the puppetmaster server with --puppetmaster-server."
	exit 1
fi

if [[ "$gitoliteserver" =~ (.*)@(.*) ]]; then
	userongit=${BASH_REMATCH[1]}
	gitoliteserver=${BASH_REMATCH[2]}
else
	userongit=`whoami`
fi


if [[ "$puppetserver" =~ (.*)@(.*) ]]; then
	useronpuppet=${BASH_REMATCH[1]}
	puppetserver=${BASH_REMATCH[2]}
else
	useronpuppet=`whoami`
fi

if [ "$puppetislocal" -eq "0" ]; then
	puppetsrcuri=puppet@$puppetserver:$puppetsource
else
	puppetsrcuri=$puppetsource
fi

#1. Dodajemy użytkownika puppet do serwera gitolite
opts="--username-for-gitolite $puppetuser@$puppetserver --server-host $gitoliteserver --client-access $useronpuppet@$puppetserver --client-target-account $puppetuser"
opts2="--extra-executable execute-script-remotely.sh --extra-executable remote/ensure-ssh-access-on-client.sh"
if [ "$debug" -eq "1" ]; then
	opts2="$opts2 --debug"
fi
if [ -n "$log" ]; then
	opts2="$opts2 --log $log"
fi
. ./execute-script-remotely.sh ./add-gitolite-user.sh $opts2 -- $opts
if [ $? -ne 0 ]; then
	errcho "Cannot create user $puppetuser@$puppetserver for gitoliteserver"
	exit 1
fi

#2. Dodajemy host gitolite do hostów w puppetmasterze
opts2="--extra-executable execute-script-remotely.sh --extra-executable remote/ensure-ssh-access-on-client.sh"
if [ "$debug" -eq "1" ]; then
	opts2="$opts2 --debug"
fi
if [ -n "$log" ]; then
	opts2="$opts2 --log $log"
fi

opts="--client-access $useronpuppet@$puppetserver --client-target-account puppet --server-access $userongit@$gitoliteserver --server-target-account gitolite --only-host-key"
. ./execute-script-remotely.sh ensure-ssh-access-setup-by-proxies.sh $opts2 -- $opts
if [ $? -ne 0 ]; then
	errcho "Cannot install gitolite's host certificate on puppet@puppetmaster"
	exit 1
fi


#Przygotowywujemy repozytorium manifest.git dla puppeta.
if [ -z "$remoterepo" ] || [ "$domerge" -eq "1" ]; then 
	# Interesuje nas szkieletowe repozytorium zrobione przez skrypt configure-puppetmaster.sh. Należy więc te repozytorium jakoś dostać
	barerepo=`mktemp -d --suffix .git`
	logexec rsync -az $useronpuppet@$puppetserver:$puppetsource/. $barerepo
	skeletonrepo=`mktemp -d`
	logmsg "cd $skeletonrepo"
	cd $skeletonrepo
	logexec git clone $barerepo $skeletonrepo
	exportlocal=1
fi

if [ -z "$remoterepo" ] && [ "$domerge" -eq "1" ]; then 
	domerge=0 #Cannot merge when there is nothing to merge. Tryb "SKELETON"
fi

if [ "$domerge" -eq "1" ]; then
	#Tryb "REBASE"
	mypipe=`mktemp --dry-run`
	opts="--base $skeletonrepo --child $remoterepo  --inplace --output-path $mypipe"
	opts2=""
	if [ "$debug" -eq "1" ]; then
		opts2="$opts2 --debug"
	fi
	if [ -n "$log" ]; then
		opts2="$opts2 --log $log"
	fi
	cd $mydir
	. ./execute-script-remotely.sh ./insert-repo-as-base-of-another.sh $opts2 -- $opts
	exportrepo=`cat $mypipe`
	exportlocal=1
	rm $mypipe
fi

if [[ "$exportlocal" -eq "1" ]] && [[ -z "$exportrepo" ]]; then
	exportrepo=$skeletonrepo
fi

if [[ "$exportlocal" -eq "1" ]]; then
	#W takim razie musimy ręcznie przenieść repozytorium do klienta
	logmsg cd $exportrepo
	cd $exportrepo
	logexec git remote remove origin
	logexec git remote add origin $puppetsrcuri
	remotetmp=`ssh $userongit@$gitoliteserver "mktemp -d"`
	$loglog
	sudo chown -R `whoami` $exportrepo
	logexec rsync -az $exportrepo/. $userongit@$gitoliteserver:$remotetmp
	function finish1 {
		ssh $userongit@$gitoliteserver sudo rm -r $remotetmp
	}
	trap finish1 EXIT 
	if [ $? -ne 0 ]; then
		errcho "Error when copying $exportrepo into $remoterepo."
		exit 1
	fi
else
	remotetmp=$remoterepo
fi


#Przenosimy repozytorium puppetmastera na serwer gitolite pod nazwą puppet/manifest lub inną, podaną przez użytkownika
opts="--ssh-address $userongit@$gitoliteserver --git-repo-uri $remotetmp --reponame $puppetrepo -c `whoami` --locally"
opts="$opts --remote-origin $puppetsrcuri"
cd $mydir
if [ -n "$log" ]; then
	opts="$opts --log $log"
	logheading ./import-into-gitolite.sh $opts
fi
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
	exit $exitstat
fi


#Upewniamy się, że gitolite@gitolite może wykonać ssh puppet@puppetmaster
opts2="--extra-executable execute-script-remotely.sh --extra-executable remote/ensure-ssh-access-on-client.sh --extra-executable remote/ensure-ssh-access-on-server.sh"
if [ "$debug" -eq "1" ]; then
	opts2="$opts2"
fi
if [ -n "$log" ]; then
	opts2="$opts2 --log $log"
fi
opts="--server-access $useronpuppet@$puppetserver --server-target-account puppet --client-access $userongit@$gitoliteserver --client-target-account gitolite"
. ./execute-script-remotely.sh ensure-ssh-access-setup-by-proxies.sh $opts2 -- $opts


#Przygowywujemy puppetmaster - zmiany są kosmetyczne i dotyczą głównie sytuacji, gdy puppetmaster jest lokalny względem gitolite.
opts="--puppet-local-repo $puppetsource"
if [ "$puppetislocal" -eq "1" ]; then
	opts="$opts --puppetmaster-is-local-to-gitolite"
fi	
opts2="--user $useronpuppet --host $puppetserver"
if [ "$debug" -eq "1" ]; then
	opts2="$opts2 --debug"
fi
if [ -n "$log" ]; then
	opts2="$opts2 --log $log"
fi
. ./execute-script-remotely.sh remote/tie-gitolite-on-puppetmaster.sh $opts2 -- $opts --puppetmaster-is-local-to-gitolite
exitstat=$?
if [ $exitstat -ne 0 ]; then
	exit $exitstat
fi

if [ "$domerge" -eq "0" ]; then
	if [ -n "$remoterepo" ]; then
		#Skoro nie dokonujemy merge, ale mamy zadane zdalne repozytorium, to musimy zamienić repozytorium /srv/puppet.git z naszym
		tmpdir=`ssh $useronpuppet@$puppetserver mktemp -d`
		#Pobieramy zdalne repozytorium na puppetmaster
		logexec ssh $useronpuppet@$puppetserver "cd $tmpdir; git clone $remoterepo $tmpdir"
		#Zapominamy o pochodzeniu zdalnego repo
		logexec ssh $useronpuppet@$puppetserver "cd $tmpdir; git remote remove origin"
		#Wpisujemy /srv/puppet.git na puppetmasterze jako źródło
		logexec ssh $useronpuppet@$puppetserver "cd $tmpdir; git remote add origin $puppetsource"
		#Upewniamy się, że repozytorium jest zapisywalne dla puppet@puppetmastera
		logexec ssh $useronpuppet@$puppetserver sudo chown -R $useronpuppet $puppetsource
		#Pozwalamy, aby przepisać na nowo historię
		logexec ssh $useronpuppet@$puppetserver "cd $puppetsource; git config receive.denynonfastforwards false"
		#Przepisujemy całą historię.
		logexec ssh $useronpuppet@$puppetserver "cd $tmpdir; git push origin --mirror"
		#Wracamy z ustawieniem na domyślną wartość. Nie chcemy, aby w przyszłości ktoś nam przepisywał historię.
		logexec ssh $useronpuppet@$puppetserver "cd $puppetsource; git config receive.denynonfastforwards true"
		#Chyba nie potrzebne...
		logexec ssh $useronpuppet@$puppetserver sudo chown -R puppet:puppet $puppetsource
		#Sprzątamy
		logexec ssh $useronpuppet@$puppetserver sudo rm -r $tmpdir
	fi
fi


#Przygotowywujemy gitolite-admin do pracy
gitoliteadminpath=`mktemp -d --suffix .git`
function finish2 {
	sudo rm -r $gitoliteadminpath
}
trap finish2 EXIT 

logmsg "cd $gitoliteadminpath"
cd $gitoliteadminpath
if [ $? -ne 0 ]; then
	errcho "Cannot create temporary directory"
	exit 1
fi
logexec git clone gitolite@$gitoliteserver:gitolite-admin
if [ $? -ne 0 ]; then
	errcho "Cannot connect with gitolite-admin. Are you sure the user `whoami` has a right to do that??"
	exit 1
fi
gitoliteadminpath="$gitoliteadminpath/gitolite-admin"

logheredoc EOT
tee $gitoliteadminpath/conf/conf.d/puppet-master.conf <<EOT >/dev/null
repo $puppetrepo
   option hook.post-receive    =   deploy-puppet
EOT

if [ -n "$puppetrsa" ]; then
	logexec scp $puppetrsa $gitoliteadminpath/keydir/$puppetuser@$puppetserver.pub
	if [ $? -ne 0 ]; then
		errcho "Cannot access the public key on $puppetrsa"
		exit 1
	fi
fi

#Zapisujemy wszystkie zmiany w konfiguracji gitolite
logmsg "cd $gitoliteadminpath"
cd $gitoliteadminpath
logexec git add .
if [ -n "$(git status --porcelain)" ]; then
	exitcode=0
	if [ -z "$(git config --global user.email)" ]; then
		$loglog
		git config --global user.email "`whoami`@`hostname`"
	fi
	if [ -z "$(git config --global user.name)" ]; then
		$loglog
		git config --global user.name "`whoami`"
	fi
	$loglog
	git commit -m "Added user puppet"
	if [ "$(git config --global push.default)" != "matching" ]; then
		logexec git config --global push.default matching
	fi
	$loglog
	git push
fi
logexec sudo rm -r `dirname $gitoliteadminpath`


#Przygowywujemy gitolite server


opts="--puppetmaster-uri $puppetsrcuri --gitolite-puppet-manifest-repo $puppetrepo"
if [ "$puppetislocal" -eq "1" ]; then
	opts="$opts --puppetmaster-is-local-to-gitolite"
else
	opts="$opts --puppetmaster-server $puppetserver"
fi	
opts2="--user $userongit --host $gitoliteserver"
if [ "$debug" -eq "1" ]; then
	opts2="$opts2 --debug"
fi
if [ -n "$log" ]; then
	opts2="$opts2 --log $log"
fi
cd $mydir
. ./execute-script-remotely.sh remote/tie-gitolite-on-gitolite.sh $opts2 -- $opts




