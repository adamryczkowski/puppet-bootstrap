#!/bin/bash
cd `dirname $0`
alias errcho='>&2 echo'

#Ten plik jest do użytku wewnętrznego import-into-gitoliet.sh
#Plik uruchamia się na serwerze gitolite i służy do włożenia repozytorium git, które już się znajduje lokalnie tutaj

#Do gitolite dodawana jest kopia repozytorium; oryginał można skasować

#add-existing-repo --repo-path <repo path> --repo-name <repo name withouth the .git suffix> [--creator-name <creator of the wild repository - only if this is intended to be a wild repo>] [--remote-origin <git origin, which will be set if the parameter is specified>]
#--repo-path - git-kompatybilna ścieżka do repozytorium, jakie chcemy dodać
#--remote-origin - Jeśli się poda, to zostanie wpisana jako ścieżka do repozytorium origin. Jeśli "none", to origin po prostu zostanie usunięte.
#--creator-name - jeśli wklejamy do bare-repo, to to jest nazwa użytkownika, który ma być właścicielem
#--repo-name - nazwa repozytorium w gitolite BEZ .git

. ./common.sh


while [[ $# > 0 ]]
do
	key="$1"
	shift

	case $key in
		--repo-path)
			repopath=$1
			shift
			;;
		--repo-name)
			reponame=$1
			shift
			;;
		--creator-name)
			repocreator=$1
			shift
			;;
		--remote-origin)
			remoteorigin=$1
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

if [ -z "$repopath" ]; then
	errcho "You must specify --repo-path parameter"
	exit 1
fi

if [ -z "$reponame" ]; then
	errcho "You must specify --repo-name parameter"
	exit 1
fi

if sudo [ -d $repopath ]; then
	logexec sudo chown -R gitolite:gitolite $repopath
fi
if sudo [ ! -d /var/lib/gitolite/repositories/$reponame.git ]; then
	logexec sudo su --login gitolite --command "git clone --bare $repopath /var/lib/gitolite/repositories/$reponame.git"
	if [ $? -ne 0 ]; then
		exit 1
	fi
fi
if [ -n "$remoteorigin" ]; then
	logexec sudo su --login gitolite --command "git -C /var/lib/gitolite/repositories/$reponame.git remote remove origin"
	if [ "$remoteorigin" != "none" ]; then
		logexec sudo su --login gitolite --command "git -C /var/lib/gitolite/repositories/$reponame.git remote add origin $remoteorigin"
	fi
fi
logexec sudo su --login gitolite --command "gitolite setup"

if [ -n "$repocreator" ]; then
	$loglog
	echo "$repocreator" | sudo su --login gitolite --command "tee /var/lib/gitolite/repositories/$reponame.git/gl-creator"
fi
