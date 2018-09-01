#!/bin/bash
cd `dirname $0`
. ./common.sh
log=/dev/stdout

a=23

#logexec echo "Próba $a"

fn="blu"

function bla {
	cd .
	echo "bla"
}

function blu {
	error syntax
}

tweaks="bla,blu,blu"
export IFS=","
for tweak in $tweaks; do
	export IFS=${oldifs}
	echo "Current tweak: ${tweak}"
	$(${tweak})
done


