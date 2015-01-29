#!/bin/bash
shopt -s extdebug
repetition_count=0

DIR=$( cd "$( dirname "${BASH_SOURCE[1]}" )" && pwd )

_ERR_HDR_FMT="%.8s %s@%s:%s:%s"
_ERR_MSG_FMT="[${_ERR_HDR_FMT}]%s \$"

msg() {
	printf "$_ERR_MSG_FMT" $(date +%T) $USER $HOSTNAME $DIR/${BASH_SOURCE[2]##*/} ${BASH_LINENO[1]}
	echo " ${@}"
}

msg2() {
	printf "$_ERR_MSG_FMT" $(date +%T) $USER $HOSTNAME $DIR/${BASH_SOURCE[2]##*/} $((${BASH_LINENO[1]} + 1 ))
	echo " ${@}"
}

function rlog()
{
	case $- in *x*) USE_X="-x";; *) USE_X=;; esac
	set +x
	case $- in *e*) USE_E="-e";; *) USE_E=;; esac
	if [ "${BASH_LINENO[0]}" -ne "$myline" ]; then
		repetition_count=0
		if [ -n "$USE_X" ]; then
			set -x
		fi
		return 0; 
	fi
	if [ "$repetition_count" -gt "0" ]; then
		if [ -n "$USE_X" ]; then
			set -x
		fi
		return -1; 
	fi
	if [ -z "$log" ]; then
		if [ -n "$USE_X" ]; then
			set -x
		fi
		return 0
	fi
	if [ "$1" == "1" ]; then
		set -x
	fi
	trap - ERR
	file=${BASH_SOURCE[1]##*/}
	line=`sed "1,$((${myline}-1)) d;${myline} s/^ *//; q" $DIR/$file`
	tmpcmd=`mktemp`
	echo "$line" > $tmpcmd
	tmpoutput=`mktemp`
	mymsg=`msg`
	exec 3>&1 4>&2 >$tmpoutput 2>&1 
	set -x
	set +e
	source $tmpcmd
	set +x
	if [ "$1" == "1" ]; then
		set -x
	fi
	exitstatus=$?
	rm $tmpcmd
	exec 1>&3 2>&4 4>&- 3>&-
	repetition_count=1 #This flag is to prevent multiple execution of the current line of code. This condition gets checked at the beginning of the function
	frstline=`sed '1q' $tmpoutput`
	[[ "$frstline" =~ ^(\++)[^+].*$ ]]
	eval 'tmp="${BASH_REMATCH[1]}"'
	pluscnt=$(( (${#tmp} + 1) *2 ))
	pluses="\+\+\+\+\+\+\+\+\+\+\+\+\+\+\+\+\+\+\+\+\+\+\+\+\+\+\+\+"
	pluses=${pluses:0:$pluscnt}
	commandlines="`awk \" gsub(/^${pluses} /,\\\"\\\")\" $tmpoutput`"
	n=0
	#There might me more then 1 command in the debugged line. The next loop appends each command to the log.
	while read -r line; do
		if [ "$n" -ne "0" ]; then
			echo "+ $line" >>$log
		else
			echo "${mymsg}$line" >>$log
			n=1
		fi
	done <<< "$commandlines"
	#Next line extracts all lines that are prefixed by sufficent number of "+" (usually 3), that are immidiately after the last line prefixed with $pluses, i.e. after the last command line.
	if [ ! -z "$USE_X" ]; then
		awk "BEGIN {flag=0} /${pluses}/ { flag=1 } /^[^+]/ { if (flag==1) print \$0; }" $tmpoutput | tee -a $log
	else
		awk "BEGIN {flag=0} /${pluses}/ { flag=1 } /^[^+]/ { if (flag==1) print \$0; }" $tmpoutput >> $log 
	fi
	if [ "$1" != "1" ]; then
		rm $tmpoutput
	else
		cp $tmpoutput /tmp/tmp.log
	fi
	if [ "$exitstatus" -ne "0" ]; then
		echo "## Exit status: $exitstatus" >>$log
	fi
	echo >>$log
	if [ -n "$USE_X" ]; then
		set -x
	fi
	if [ -n "$USE_E" ]; then
		set -e
	fi
	trap 'errorhdl' ERR
	if [ "$exitstatus" -ne "0" ]; then
		exit $exitstatus
	fi
	return -1
}

log_next_line='eval if [ -n "$log" ]; then myline=$(($LINENO+1)); trap "rlog" DEBUG; fi;'
logoff='trap - DEBUG'
loglog='eval if [ -n "$log" ]; then myline=$(($LINENO+1)); trap "rlog" DEBUG; fi;'
loglogx='eval if [ -n "$log" ]; then myline=$(($LINENO+1)); trap "rlog 1" DEBUG; fi;'

function logexec()
{	
	case $- in *x*) USE_X="-x";; *) USE_X=;; esac
	set +x
	case $- in *e*) USE_E="-e";; *) USE_E=;; esac
	set +e
	if [ "$1" == "1" ]; then
		common_debug=1
		shift
	else
		common_debug=0
	fi
	if [ "$common_debug" -eq "1" ]; then
		set -x
	fi
	trap - ERR
	file=${BASH_SOURCE[1]##*/}
	linenr=$((${BASH_LINENO[0]}-1))
	if [ ! -f "$DIR/$file" ]; then
		msg "Cannot find file $DIR/$file!!" >>$log
		line="$@"
		echo "$line" >>$log
	else
		line=`sed "1,${linenr} d;$((${linenr}+1)) s/^\s*//; q" $DIR/$file`
		line=${line:${#FUNCNAME[0]}}
	fi
	tmpcmd=`mktemp`
	echo "$line" > $tmpcmd
	tmpoutput=`mktemp`
	if [ -n "$log" ]; then
		mymsg=`msg`
		exec 3>&1 4>&2 >$tmpoutput 2>&1 
		set -x
		source $tmpcmd
		set +x
		if [ "$common_debug" -eq "1" ]; then
			set -x
		fi
		exitstatus=$?
		exec 1>&3 2>&4 4>&- 3>&-
		line=`awk '/^\+\+/ { print $0; exit; }' $tmpoutput`
		echo "${mymsg}${line:3}" >>$log
		if [ ! -z "$USE_X" ]; then
			awk 'BEGIN {start=0;stop=0} /^\+\+/ { if (start==0) start=NR+1; else stop=1; } /^\+[^\+]/ { if (start>0) {stop=1;} } 1 { if (start>0 && NR>=start && stop==0) print $0; }' $tmpoutput | tee -a $log
		else
			awk 'BEGIN {start=0;stop=0} /^\+\+/ { if (start==0) start=NR+1; else stop=1; } /^\+[^\+]/ { if (start>0) {stop=1;} } 1 { if (start>0 && NR>=start && stop==0) print $0; }' $tmpoutput >> $log
		fi
		rm $tmpoutput
		if [ "$exitstatus" -ne "0" ]; then
			echo "## Exit status: $exitstatus" >>$log
		fi
		echo >>$log
	else
		source $tmpcmd
		exitstatus=$?
	fi
	rm $tmpcmd
	trap 'errorhdl' ERR
	if [ "$exitstatus" -ne "0" ]; then
		if [ -n "$USE_E" ]; then
			set -e
		fi
		if [ -n "$USE_X" ]; then
			set -x
		fi
		exit $exitstatus
	fi
	if [ -n "$USE_E" ]; then
		set -e
	fi
	if [ -n "$USE_X" ]; then
		set -x
	fi
}

function logmsg()
{
	case $- in *x*) USE_X="-x";; *) USE_X=;; esac
	set +x
	if [ -n "$log" ]; then
		echo "`msg` $@" >>$log
	fi
	if [ -n "$USE_X" ]; then
		echo $?
		set -x
	fi
}

previousmsg() {
	printf "$_ERR_MSG_FMT" $(date +%T) $USER $HOSTNAME $DIR/${BASH_SOURCE[3]##*/} ${BASH_LINENO[2]}
	echo "${@}"
}

function logatpreviousmsg()
{
	case $- in *x*) USE_X="-x";; *) USE_X=;; esac
	set +x
	if [ -n "$log" ]; then
		echo "`previousmsg` $@" >>$log
	fi
	if [ -n "$USE_X" ]; then
		echo $?
		set -x
	fi
}


function errcho()
{
	logmsg $@
}


function logheredoc()
{
	case $- in *x*) USE_X="-x";; *) USE_X=;; esac
	set +x
	if [ -n "$log" ]; then
		trap - ERR
		token=$1
		shift
		file=${BASH_SOURCE[1]##*/}
		linenr=$((${BASH_LINENO[0]} + 1 ))
		lines=`sed -n "$((${linenr})),/^$token$/p" $DIR/$file`
		n=0
		while read -r line; do
			if [ "$n" -ne "0" ]; then
				echo "$line" >>$log
			else
				msg2 "$line" >>$log
				n=1
			fi
		done <<< "$lines"
		trap 'errorhdl' ERR
	fi
	if [ -n "$USE_X" ]; then
		set -x
	fi
}

function loglog()
{
	case $- in *x*) USE_X="-x";; *) USE_X=;; esac
	set +x
	if [ "$1" == "1" ]; then
		set -x
	fi
	if [ -n "$log" ]; then
		trap - ERR
		file=${BASH_SOURCE[1]##*/}
		linenr=$((${BASH_LINENO[0]} ))
		lines=`sed "1,${linenr} d;$((${linenr}+1)) s/^\s*//; q" $DIR/$file`
		n=0
		while read -r line; do
			if [ "$n" -ne "0" ]; then
				echo "$line" >>$log
			else
				msg2 "$line" >>$log
				n=1
			fi
		done <<< "$lines"
		trap 'errorhdl' ERR
	fi
	if [ -n "$USE_X" ]; then
		set -x
	fi
}

function logheading()
{
	if [ -n "$log" ]; then
		echo >>$log
		echo "################## $@ ################">>$log
		echo >>$log
	fi
}

function errorhdl()
{
	case $- in *x*) USE_X2="-x";; *) USE_X2=;; esac
	set +x
	if [ "$repetition_count" -ne "0" ]; then
		if [ -n "$USE_X" ]; then
			set -x
		fi
		if [ -n "$USE_X2" ]; then
			set -x
		fi
		return
	fi
	if [ -n "$log" ]; then
		file=${BASH_SOURCE[1]##*/}
		myline=${BASH_LINENO[0]}
		line=`sed "1,$((${myline}-1)) d;${myline} s/^ *//; q" $DIR/$file`
		msg "$line" >>$log
		echo "Trapped ERROR in the line above!!" >>$log
	fi
	if [ -n "$USE_X" ]; then
		set -x
	fi
	if [ -n "$USE_X2" ]; then
		set -x
	fi
}

trap 'errorhdl' ERR

