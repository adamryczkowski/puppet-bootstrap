#!/bin/bash

function add_dhcpd_entry {
	local subnet=$1
	local netmask=$2
	local range_from=$3
	local range_to=$4
	local dirty
	local oldvalue
	local oldvalue1
	local oldvalue2
	install_apt_package augeas-tools augtool
	if ! augtool -L -A --transform "Dhcpd incl /etc/dhcp/dhcpd.conf" match "/files/etc/dhcp/dhcpd.conf/subnet/network" | grep -q $subnet; then
		logheredoc EOT
		sudo augtool -L -A --transform 'Dhcpd incl /etc/dhcp/dhcpd.conf' <<EOT >/dev/null
clear '/files/etc/dhcp/dhcpd.conf/subnet[last() + 1]'
set "/files/etc/dhcp/dhcpd.conf/subnet[last()]/network" "$subnet"
set "/files/etc/dhcp/dhcpd.conf/subnet[last()]/netmask" "$netmask"
save
EOT
		dirty=1
	fi

	oldvalue=$(augtool -L -A --transform "Dhcpd incl /etc/dhcp/dhcpd.conf" get "/files/etc/dhcp/dhcpd.conf/subnet[network='$subnet']/netmask" | sed -En 's/\/.* = \"?([^\"]*)\"?$/\1/p')
	if [ "$netmask" != "$oldvalue" ]; then
		logexec sudo augtool -L -A --transform "Dhcpd incl /etc/dhcp/dhcpd.conf" set "/files/etc/dhcp/dhcpd.conf/subnet[network='$subnet']/netmask" "${netmask}" >/dev/null
		dirty=1
	fi
	
	oldvalue1=$(augtool -L -A --transform "Dhcpd incl /etc/dhcp/dhcpd.conf" get "/files/etc/dhcp/dhcpd.conf/subnet[network='$subnet']/range/from" | sed -En 's/\/.* = \"?([^\"]*)\"?$/\1/p')
	oldvalue2=$(augtool -L -A --transform "Dhcpd incl /etc/dhcp/dhcpd.conf" get "/files/etc/dhcp/dhcpd.conf/subnet[network='$subnet']/range/to" | sed -En 's/\/.* = \"?([^\"]*)\"?$/\1/p')
	if [ "$range_from" != "$oldvalue1" ] || [ "$range_to" != "$oldvalue2" ]; then
		logheredoc EOT
		sudo augtool -L -A --transform 'Dhcpd incl /etc/dhcp/dhcpd.conf' <<EOT >/dev/null
set "/files/etc/dhcp/dhcpd.conf/subnet[network='$subnet']/range/from" "${range_from}"
set "/files/etc/dhcp/dhcpd.conf/subnet[network='$subnet']/range/to" "${range_to}"
save
EOT
		dirty=1
	fi
	
	if [ "$dirty" == "1" ]; then
		return 0
	fi
	return 1
}

function edit_dhcpd {
	local key=$1
	local value=$2
	if [ "${value}" == "<ON>" ]; then
		if augtool -L -A --transform "Dhcpd incl /etc/dhcp/dhcpd.conf" get "/files/etc/dhcp/dhcpd.conf/${key}" | grep -q '(o)'; then
			logexec sudo augtool -L -A --transform "Dhcpd incl /etc/dhcp/dhcpd.conf" clear "/files/etc/dhcp/dhcpd.conf/option/${key}" >/dev/null
			return 0
		fi
	fi
	if [ "${value}" == "<OFF>" ]; then
		if augtool -L -A --transform "Dhcpd incl /etc/dhcp/dhcpd.conf" get "/files/etc/dhcp/dhcpd.conf/${key}" | grep -q '(none)'; then
			logexec sudo augtool -L -A --transform "Dhcpd incl /etc/dhcp/dhcpd.conf" rm "/files/etc/dhcp/dhcpd.conf/option/${key}" >/dev/null
			return 0
		fi
	fi
	oldvalue=$(augtool -L -A --transform "Dhcpd incl /etc/dhcp/dhcpd.conf" get "/files/etc/dhcp/dhcpd.conf/option/${key}" | sed -En 's/\/.* = \"?([^\"]*)\"?$/\1/p')
	if [ "$value" != "$oldvalue" ]; then
		logexec sudo augtool -L -A --transform "Dhcpd incl /etc/dhcp/dhcpd.conf" set "/files/etc/dhcp/dhcpd.conf/option/${key}" "${value}" >/dev/null
		return 0
	fi
	return 1
}

function random_mac {
	local prefix=$1
	local len=${#prefix}
	local infix
	local hexchars
	local end
	if [ $len -lt 3 ]; then
		infix=":"
	else
		infix=${prefix:2:1}
#		echo "infix=$infix"
	fi
	if [[ ${prefix:$((len-1)):1} == ${infix} ]]; then
		prefix="${prefix:0:$((len-1))}"
#		echo "prefix=$prefix"
	fi
	let "nwords = (${len}+3-1)/3"
#	echo "nwords=$nwords"
	let "n = 12-2*nwords"
#	echo "n=$n"
	hexchars="0123456789ABCDEF"
	end=$( for i in $(seq ${n}); do echo -n ${hexchars:$(( $RANDOM % 16 )):1} ; done | sed -e "s/\(..\)/${infix}\1/g" )
	echo ${prefix}${end}
}

function parse_URI {
	local URI="$1"
	local pattern='^(([[:alnum:]]+)://)?(([[:alnum:]]+)@)?([^:^@]+)(:([[:digit:]]+))?$'
	if [[ "$URI" =~ $pattern ]]; then
		proto=${BASH_REMATCH[2]}
		user=${BASH_REMATCH[4]}
		ip=${BASH_REMATCH[5]}
		port=${BASH_REMATCH[7]}
		return 0
	else
		errcho "You must put proper address of the ssh server in the first argument, e.g. user@host.com:2022"
		return 1
	fi
}

function add_host {
	local host=$1
	local ip=$2
	local HOSTS_LINE="${ip} ${host}"
	if [ ! -n "$(grep ${host} /etc/hosts)" ]; then
		$loglog
		echo "$HOSTS_LINE" | sudo tee -a /etc/hosts
	fi
}

function enable_host {
	local host=$1
	local ip=$2
	local HOSTS_LINE="${ip} ${host}"
	local pattern=" *#? *${ip} +${host}"
	pattern=${pattern//./\\.} #replace . into \.
	if grep  -E "$pattern" /etc/hosts;  then #element is already added
	   on_pattern=" *# *${ip} +${host}"
   	if grep  -E "$on_pattern" /etc/hosts; then #element is not already turned on
   	   sudo sed -i -r "s/${pattern}/${ip} ${host}/g" /etc/hosts
   	fi
	else
	   add_host "$1" "$2"
	fi
}

function disable_host {
	local host=$1
	local ip=$2
	local HOSTS_LINE="${ip} ${host}"
	local pattern=" *#? *${ip} +${host}"
	pattern=${pattern//./\\.} #replace . into \.
	if ! grep  -E "$pattern" /etc/hosts;  then #element is already added
	   add_host "$1" "$2"
	fi
   on_pattern=" *# *${ip} +${host}"
	if ! grep  -E "$on_pattern" /etc/hosts; then #element is not already turned on
	   sudo sed -i -r "s/${pattern}/# ${ip} ${host}/g" /etc/hosts
	fi
}


function get_iface_ip {
	local iface=$1
	if ifconfig $local_n2n_iface 2>/dev/null >/dev/null; then
		ip addr show $1 | awk '$1 == "inet" {gsub(/\/.*$/, "", $2); print $2}'
		return 0
	else
		return 1
	fi

}

function is_host_up {
	ping -c 1 -w 1  $1 >/dev/null
}

function get_local_ip {
	local line=$(ip route get 1)
	local pattern='^.* src (.*) uid'
	if [[ $line =~ $pattern ]]; then
		echo "${BASH_REMATCH[1]}"
		return
	else
		errcho "Cannot get local ip from $line"
		return -1
	fi
}
