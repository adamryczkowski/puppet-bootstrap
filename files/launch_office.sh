#!/bin/bash

#This script calls either Excel, Word or PowerPoint with arguments that get 
#translated into paths visible to Wine.
#
#It does this by reading through the $WINEPREFIX/dosdevices directory and looking
#for working symlinks pointing to existing directories. It then checks if the path
#of each argument is inside any of these links. If more than one exist, it chooses the
#shortest.
#
# Script created by
# Adam Ryczkowski
# adam@statystyka.net

if [ -d /opt/Office2007 ]; then
	export WINEPREFIX="/opt/Office2007"
else
	export WINEPREFIX="/home/${USER}/.PlayOnLinux/wineprefix/Office2007"
fi

if [ ! -d "$WINEPREFIX" ]; then
	echo "Cannot find wineprefix in $WINEPREFIX" > /dev/stderr
	exit 1
fi

case $1 in
	excel)
	prg="EXCEL.EXE"
	;;
	word)
	prg="WINWORD.EXE"
	;;
	powerpoint)
	prg="POWERPNT.EXE"
	;;
	*)
	echo "Error: Unknown option: $1" >&2
	exit 1
	;;
esac
shift

function get_best_wine_path {
	local docpath="$1"
	local answer
	local best_answer
	local stripped_docpath
	local windows_docpath
	for file in ${WINEPREFIX}/dosdevices/*; do
		if [ -L "$file" ]; then
			base_candidate=$(readlink -f "$file")
			if [[ "$docpath" == "${base_candidate}"* ]]; then
				stripped_docpath="${docpath##${base_candidate}/}"
				drive=$(basename "$file")
				windows_docpath="${drive}\\${stripped_docpath//\//\\\\}" #Replace backslash with slash
				if [ -z "$best_answer" ]; then
					best_answer="$windows_docpath"
				else
					if (( "${#windows_docpath}" < "${#best_answer}" )); then
						best_answer="$windows_docpath"
					fi
				fi
			fi
		fi
	done
	echo "$best_answer"
}

function get_special_dir {
	local dirtype=$1
	local user=$2
	local ans=""
	local HOME
	local pattern
	local folder
	HOME=$(get_home_dir $user)
	if [ -f "${HOME}/.config/user-dirs.dirs" ]; then
		line=$(grep "^[^#].*${dirtype}" "${HOME}/.config/user-dirs.dirs")
		pattern="^.*${dirtype}.*=\"?([^\"]+)\"?$"
		if [[ "$line" =~ $pattern ]]; then
			folder=${BASH_REMATCH[1]}
			ans=$(echo $folder | envsubst )
			if [ "$ans" == "$HOME" ]; then
				ans=""
			fi
		fi
	fi
	echo "$ans"
}


doc_dir=$(get_special_dir DOCUMENTS "$USER")
desktop_dir=$(get_special_dir DOCUMENTS "$USER")

declare -a args

for var in "$@"
do
	arg=$(readlink -f "$var")
	if [ -n "$arg" ]; then
		docpath=$(get_best_wine_path "${arg}")
		args+=("$docpath")
	else
		args+=("$var")
	fi
done

wine "${WINEPREFIX}/drive_c/Program Files/Microsoft Office/Office12/${prg}" "${args[@]}" 

