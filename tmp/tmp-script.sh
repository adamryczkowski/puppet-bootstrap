#!/bin/bash


var=adam@stat.net:22

regex="((git)|(ssh)\:\/?\/?)?([[:alnum:]]+)@([[:alnum:]\.]+)(\:([[:digit:]]+))?"

if [[ "$var" =~ $regex ]]; then
	echo "1: «${BASH_REMATCH[1]}», 2: «${BASH_REMATCH[2]}», 3: «${BASH_REMATCH[3]}», 4: «${BASH_REMATCH[4]}», 5: «${BASH_REMATCH[5]}» 6: «${BASH_REMATCH[6]}» 7: «${BASH_REMATCH[7]}»"
else
	echo "NO MATCH"
fi

exit 0

if [ -f mylog.log ]; then
	rm mylog.log
fi

. ../common.sh
log=$DIR/mylog.log

cd /

$loglog
cd /nie/istniejacy/katalog || errorcode=$?

$log_next_line
ls / >/dev/null || exitcode=$?

$loglog
echo "server = $fqdn" | tee -a /tmp/tmp.txt

exit
mkdir /ddad/adad/dad #Generates an error


exit



$loglog
			echo 'Defaults         !tty_tickets' | tee /tmp/temp/bla.txt >/dev/null

exit
exit

#$log_next_line
#echo "$var1 veth $var2 10" | tee -a /tmp/temp/bla-bla.tmp

#$log_next_line
#echo 1
#$log_next_line
#echo 2
#$log_next_line
#echo 3
#$log_next_line
#echo 4


var1=echo
var2=mik


#logheredoc EOT
#tee /tmp/temp/bla-bla.tmp <<EOT 
#lxc.include = /etc/lxc/default.conf
#lxc.id_map = u 0 100000 65536
#lxc.id_map = g 0 100000 65536
#EOT

if [ -f /tmp/temp/bla-bla.tmp ]; then
	rm /tmp/temp/bla-bla.tmp
fi

#if [ -n "$log" ]; then 
#	myline=29; 
#	trap "preexec" DEBUG 
#fi


	logheredoc EOT
tee /tmp/temp/bla.txt <<EOT
lxc.include = /etc/lxc/default.conf
lxc.id_map = u 0 100000 65536
lxc.id_map = g 0 100000 65536
EOT

exit

#logexec $var1 "Lubię $var2" 

#	logexec sudo service lxc-net stop || true

#var1=sudo
#	loglog
#$var1 service lxc-net start 


a=example
x=a

#            logexec2 mkdir /ddad/adad/dad
#exit
$log_next_line
echo "KUKU!"
$log_next_line
echo $x
$log_next_line
echo ${!x}
$log_next_line
echo ${!x} > /dev/null
$log_next_line
echo "Proba">/tmp/mtmp.txt
$log_next_line
touch ${!x}.txt
$log_next_line
if [ $(( ${#a} + 6 )) -gt 10 ]; then echo "Too long string"; fi
$log_next_line
echo "\$a and \$x">/dev/null
$log_next_line
echo $x
$log_next_line
ls -l
$log_next_line
mkdir /ddad/adad/dad #Generates an error

exit

logexec2 echo "KUKU!"
#log_next_line
logexec2 echo $x
#log_next_line
logexec2 echo ${!x}
#log_next_line
logexec2 echo ${!x} > /dev/null
#log_next_line
logexec2 echo "Proba">/tmp/mtmp.txt
#log_next_line
logexec2 touch ${!x}.txt
#log_next_line
#logexec2 if [ $(( ${#a} - 6 )) -gt 10 ]; then echo "Too long string"; fi
#log_next_line
logexec2 echo "\$a and \$x">/dev/null
#log_next_line
logexec2 echo $x

