#!/bin/bash
cd `dirname $0`
. ./common.sh

#Program wstawia zadane --base repozytorium na początek historii repozytorium --child, produkując repozytorium, które wygląda tak, jakby ktoś do repozytorium --base dodał masę commitów (łącznie z branch) tak, że ostateczne repozytorium wygląda tak, jak --child.
#Ścieżka do utworzonego repozytorium jest przekazana do pipe /tmp/baserepo.pipe lub do innego miejsce

#insert-repo-as-base-of-another.sh --base|-b <kompatybilna z git ścieżka do bazowego repozytorium> -c|--child <kompatybilna z git ścieżka do repozytorium dodawanego na wierzch> [--inplace] [--push]
#--inplace  - jeśli podany, to w destruktywny sposób potraktujemy repozytorium podane jako bazowe. Jeśli repozytorium bazowe jest duże, to oszczędzimy trochę dysk twardy -o|--output-path <ścieżka do pliku/pipe do którego zostanie wpisana ścieżka utworzonego repozytorium>


alias errcho='>&2 echo'
clonebase=1

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--base|-b)
	base=$1
	shift
	;;
	-c|--child)
	child=$1
	shift
	;;	
	--inplace)
	clonebase=0
	;;
	-o|--output-path)
	output=$1
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

if [ -z "$output" ]; then
	errcho "--output parameter is mandatory. Existing."
	exit 1
fi

if [ -z "$base" ]; then
	errcho "--base parameter is mandatory. Existing."
	exit 1
fi

if [ -z "$child" ]; then
	errcho "--child parameter is mandatory. Existing."
	exit 1
fi

if [ "$clonebase" -eq "1" ]; then
	basedir=`mktemp -d --suffix .git`
	logexec cd $basedir
	logexec git clone $base base
	if [ $? -ne 1 ]; then
		errcho "Cannot clone $base repository. Aborting."
		exit 1
	fi
	base=$basedir/base
fi


cd $base
if [ $? -ne 0 ]; then
	errcho "Cannot cd into directory $base on host $(hostname). Aborting."
	exit 1
fi
logexec git remote add new $child
logexec git remote update 
if [ $? -ne 0 ]; then
	errcho "Cannot pull history from $child. Aborting."
	exit 1
fi

FIRSTREMOTECOMMIT=`git rev-list --max-parents=0 --remotes=new`
logexec git read-tree -u --reset $FIRSTREMOTECOMMIT

for branch in $(git for-each-ref --format='%(refname)' refs/remotes/new/); do
	br=`basename $branch`
	if [ -z "$LASTLOCALCOMMIT" ]; then
		logexec git checkout -q -b $br
		logexec git commit -q -C $FIRSTREMOTECOMMIT
		if [ $? -ne 0 ]; then
			exit 1
		fi
		LASTLOCALCOMMIT=`git rev-parse HEAD`
		FIRSTBRANCH=$br
	else
		logexec git checkout -q -b $br $LASTLOCALCOMMIT
	fi
	logexec git cherry-pick -X theirs $FIRSTREMOTECOMMIT..refs/remotes/new/$br
done
logexec git remote remove new
logexec git symbolic-ref HEAD refs/heads/$FIRSTBRANCH

echo "$base">$output

