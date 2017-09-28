#!/bin/bash 

function install_apt_package {
	ans=0
	package=$1
	command=$2
	if [ -n "$command" ]; then
		if ! which "$command">/dev/null  2> /dev/null; then
			do_update
			logexec sudo apt-get --yes --force-yes -q install "$package"
			return 0
		fi
	else
		if ! dpkg -s "$package">/dev/null  2> /dev/null; then
			do_update
			logexec sudo apt-get --yes --force-yes -q install "$package"
			return 0
		fi
	fi
	return 1
}  

function install_apt_packages {
	ans=0
	to_install=""
	packages="$@"
	for package in ${packages[@]}
	do
		if ! dpkg -s "$package">/dev/null  2> /dev/null; then
			to_install="${to_install} ${package}"
		fi
	done
	if [[ "${to_install}" != "" ]]; then
		do_update
		logexec sudo apt-get --yes --force-yes -q  install $to_install
		return 0
	fi
	return 1
}  


function do_update {
	if [ "$flag_need_apt_update" == "1" ]; then
		logexec sudo apt update
		flag_need_apt_update=0
		return 0
	fi
	return 1
}

function do_upgrade {
	do_update
	logexec sudo apt upgrade --yes
	return 0
}

function add_ppa {
	the_ppa=$1
	
	if ! grep -q "^deb .*$the_ppa" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then

		install_apt_package software-properties-common add-apt-repository

		logexec sudo add-apt-repository -y ppa:ubuntu-lxc/lxd-stable
		flag_need_apt_update=1
		return 0
	fi
	return 1
}

function edit_bash_augeas {
	file=$1
	var=$2
	value=$3
	install_apt_package augeas-tools augtool
	oldvalue=$(sudo augtool -L -A --transform "Shellvars incl $file" get "/files${file}/${var}" | sed -En 's/\/.* = \"?([^\"]*)\"?$/\1/p')
	if [ "$value" != "$oldvalue" ]; then
		logexec sudo augtool -L -A --transform "Shellvars incl $file" set "/files${file}/${var}" "${value}" >/dev/null
	fi
}

function add_dhcpd_entry {
	subnet=$1
	netmask=$2
	range_from=$3
	range_to=$4
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
	key=$1
	value=$2
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

function simple_systemd_service {
	name=$1
	description="$2"
	program=$3
	shift;shift;shift
	args="$@"
	
	if [ ! -f "$program" ]; then
		if which $program >/dev/null; then
			program=$(which ${program})
		fi
	fi
	
cat > /tmp/tmp_service <<EOT
[Unit]
Description=$description

[Service]
ExecStart="$program" $args

[Install]
WantedBy=multi-user.target
EOT
	if ! cmp --silent /tmp/${name}.service /lib/systemd/system/${name}.service; then
logheredoc EOT
sudo tee /lib/systemd/system/${name}.service>/dev/null <<EOT
[Unit]
Description=$description

[Service]
ExecStart="$program" $args

[Install]
WantedBy=multi-user.target
EOT
		logexec sudo systemctl daemon-reload
		is_active=$(systemctl is-active $name)
		if [ ! "$is_active" == "active" ]; then
			logexec sudo systemctl enable $name
		fi
	fi 

	if ! systemctl status $name | grep -q running; then
		logexec sudo service $name start
		return 0
	fi
	return 1
}

function random_mac {
	prefix=$1
	len=${#prefix}
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
	URI="$1"
    pattern='^(([[:alnum:]]+)://)?(([[:alnum:]]+)@)?([^:^@]+)(:([[:digit:]]+))?$'
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

function get_iface_ip {
	iface=$1
	if ifconfig $local_n2n_iface 2>/dev/null >/dev/null; then
		ip addr show $1 | awk '$1 == "inet" {gsub(/\/.*$/, "", $2); print $2}'
		return 0
	else
		return 1
	fi

}

function apply_patch {
	orig=$1
	patch=$2
	tmp=/tmp/tmp_patched
	patch --batch $orig -i $patch -o $tmp 2>/dev/null
	if ! cmp -s $tmp $orig; then
		cp $orig $tmp
		logexec cat $patch
		logexec sudo patch --batch $tmp -i $patch -o $orig
		return $?
	fi
	return 1
}
