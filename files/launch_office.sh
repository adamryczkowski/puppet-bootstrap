#!/bin/bash
export WINEPREFIX="$(readlink -f /home/${USER}/.PlayOnLinux/wineprefix/Office2007)"

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


cd "${WINEPREFIX}/drive_c/Program Files/Microsoft Office/Office12"
if [ "$@" != "" ]; then
	declare -a args

	for var in "$@"; do
		arg=$(readlink -f "$var")
	#	openin=`dirname "${arg}"`
		#echo "arg: ${arg}" >/tmp/kiki
		if [ -n "$arg" ]; then
			drives="${WINEPREFIX}/dosdevices/?:"
			for drive in $drives; do
				basepath=$(readlink "$drive")
				drive=$(basename $drive)
	#			basepath='/home/Adama-docs/Adam'
				if [ -n "$basepath" ]; then
					if [[ $arg == "${basepath}"* ]]; then
						basepath=${basepath//\//\\\/}
						docpath=${arg/${basepath}/H:}
						break;
	#				else
	#					docpath="${drive}/${arg}"
					fi
				fi
			done
			#bash inline string replacement. Replaces / ("\/") with \ ("\\")
			docpath=${docpath//\//\\}
		fi
		args+=("$docpath")
	done
	wine "start" "${args[@]}" 
else
	wine "${prg}" "${args[@]}" 
fi
