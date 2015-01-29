#!/bin/bash
cd `dirname $0`

if [ -f common.sh ]; then
	. ./common.sh
fi

#To jest skrypt, który wypluwa wiersz, jaki trzeba dodać do /etc/subuid

#syntax:
#max-subuid.sh --user <username> --subuid|--subgid --add|--show|--check
#--add - dodaje wpis do pliku /etc/subuid lub subgid.
#--show - zwraca rekord <user>:<baseid>:<cnt> albo istniejący, albo taki, jaki trzeba dodać. Jeśli rekordu nie ma, to funkcja zwraca errorlevel=1
#--check - sprawdza, czy zadany rekord już istnieje i zwraca wynik jako errorlevel.

alias errcho='>&2 echo'

mode=
action=show
userbaseid=
useridcnt=

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--user)
	user="$1"
	shift
	;;
	--baseid)
	userbaseid="$1"
	shift
	;;
	--idcnt)
	useridcnt="$1"
	shift
	;;
	--subuid)
	mode=subuid
	;;
	--subgid)
	mode=subgid
	;;
	--add)
	action=add
	;;
	--check)
	action=check
	;;
	--show)
	action=show
	;;
	*)
	echo "Unkown parameter '$key'. Aborting."
	exit 1
	;;
esac
done

#if [ -n "$userbaseid" ] && [ -z "$useridcnt" ]; then
	#	useridcnt=65536
#fi

if [ -z "$user" ]; then
	echo "Missing --user! " >/dev/stderr
	exit 1
fi

if [ -z "$mode" ]; then
	echo "Missing --subuid or --subgid! " >/dev/stderr
	exit 1
fi

function findmaxid
#Funkcja zwraca max. wolny i dostępny numer id. 
#Funkcja używa parametrów: $mode
#Zwracane globalne zmienne: maxid
{
	#Stąd zaczynamy szukać
	local curuser=0
	local curbaseid=0
	local maxid=100000 
	foundbaseid=
	while read line || [[ -n $line ]]; do
		regex1="^\s*$"
		if [[ ! $line =~ $regex1 ]]; then
			slot1="[[:lower:]]+[[:alnum:]]*"
			slot2="[[:digit:]]{1,9}"
			slot3="$slot2"
			regex1="^($slot1):($slot2):($slot3)\s*$"
			if [[ "$line" =~ $regex1 ]]; then
				curbaseid=${BASH_REMATCH[2]}
				curidcnt=${BASH_REMATCH[3]}
				if [ "$((curbaseid+curidcnt))" -gt "$maxid" ]; then
					maxid=$((curbaseid+curidcnt))
				fi
			fi
		fi
	done </etc/$mode
}

function finduserid
#Funkcja wyszukuje wpisy dla danego użytkownika i zwraca ostatni z nich razem z krotnością
#Funkcja używa parametrów: $mode, $user, $userbaseid, $useridcnt
#Zwracane globalne zmienne: foundbaseid, foundcnt, foundidcnt, fullmatch
{
	#Stąd zaczynamy szukać
	local maxid=100000 
	foundbaseid=
	foundcnt=0
	foundidcnt=
	local curuser=
	local curbaseid=
	fullmatch=0
	local curidcnt=
	while read line || [[ -n $line ]]; do
		regex1="^\s*$"
		if [[ ! $line =~ $regex1 ]]; then
			slot1="[[:lower:]]+[[:alnum:]]*"
			slot2="[[:digit:]]{1,9}"
			slot3="$slot2"
			regex1="^($slot1):($slot2):($slot3)\s*$"
			if [[ "$line" =~ $regex1 ]]; then
				curuser=${BASH_REMATCH[1]}
				curbaseid=${BASH_REMATCH[2]}
				curidcnt=${BASH_REMATCH[3]}
				if [[ "$curuser" == "$user" ]]; then
					foundcnt=$((foundcnt+1))
					foundbaseid=$curbaseid
					foundidcnt=$curidcnt
					if [ "$curbaseid" == "$userbaseid" ] && [ "$curidcnt" == "$useridcnt" ]; then
						fullmatch=1
					fi
				fi
			fi
		fi
	done </etc/$mode
}

case $action in
	add)
	removeall=0
	finduserid
	if [ "$foundcnt" -gt "0" ]; then
		#Znaleziono już wpis dla tego użytkownika.
		if [ "$foundcnt" -gt "1" ]; then
			removeall=1
		else
			if [ -z "$useridcnt" ]; then
				useridcnt=$foundidcnt
			fi
			if [ -z "$userbaseid" ]; then
				userbaseid=$foundbaseid
			fi
			if [ "$useridcnt" -ne "$foundidcnt" ] || [ "$userbaseid" != "$foundbaseid" ]; then
				#Należy najpierw usunąć istniejący rekord, bo się nie zgadza
				removeall=1
			fi
		fi
	else
		#rekordu nie ma
		findmaxid
		if [ -z "$useridcnt" ]; then
			useridcnt=65536
		fi
		if [ -z "$userbaseid" ]; then
			userbaseid=$maxid
		fi
	fi
				
	if [ "$removeall" == "1" ]; then
		slot2="[[:digit:]]{1,9}"
		regex1="^($user):($slot2):($slot2)\s*$"
		sudo sed -i -r "/$regex1/d" /etc/$mode
	else
		#Rekord już istniał i nie trzeba niczego zmieniać
		exit 0
	fi
		
	line="$user:$userbaseid:$useridcnt"
	echo "$line" | sudo tee -a /etc/$mode
	sudo usermod --add-subuids $userbaseid-$((useridcnt+userbaseid)) $user
	;;
	show)
	removeall=0
	finduserid
	if [ "$foundcnt" -gt 0 ]; then
		#Znaleziono już wpis dla tego użytkownika. Wypisujemy ostanti.
		echo "$user:$foundbaseid:$foundidcnt"
		exit 0
	else
		#rekordu nie ma, trzeba stworzyć nowy
		findmaxid
		if [ -z "$useridcnt" ]; then
			useridcnt=65536
		fi
		if [ -z "$userbaseid" ]; then
			userbaseid=$maxid
		fi
		echo "$user:$userbaseid:$useridcnt"
		exit 1
	fi
	;;
	check)
	finduserid
	if [ "$foundcnt" -gt 0 ]; then
		#Znaleziono już wpis dla tego użytkownika.
		#Jest więcej niż jeden, ale zakładamy że ok.
		if [ "$fullmatch" == "1" ]; then
			exit 0
		else
			#multiple records exists, but no one is good.
			exit 2 
		fi
	else
		#Nic nie znaleziono
		exit 1
	fi
	;;
	*)
	echo "INTERNAL ERROR." >/dev/stderr
	exit 2
	;;
esac



