#!/bin/bash 

function purge_apt_package {
	ans=0
	package=$1
	if dpkg -s "$package">/dev/null  2> /dev/null; then
		logexec sudo apt-get --yes --force-yes -q purge "$package"
		return 0
	fi
	return 1
}

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

function get_ubuntu_version {
	tmp=$(lsb_release -a 2>/dev/null | grep Release)
	pattern='^Release:\s*([0-9]+)\.([0-9]+)$'
	if [[ "$tmp" =~ $pattern ]]; then
		echo ${BASH_REMATCH[1]}${BASH_REMATCH[2]}
		return 0
	fi
	return 1
}

function install_apt_package_file {
	ans=0
	filename=$1
	package=$2
	if ! dpkg -s "$package">/dev/null  2> /dev/null; then
		logexec sudo dpkg -i $filename
		return 0
	fi
	return 1
}  

function install_pip3_packages {
	ans=0
	to_install=""
	packages="$@"
	for package in ${packages[@]}
	do
		if ! pip3 list | grep -qF "$package" >/dev/null  2> /dev/null; then
			to_install="${to_install} ${package}"
		fi
	done
	if [[ "${to_install}" != "" ]]; then
		do_update
		logexec sudo -H pip3 install $to_install
		return 0
	fi
	return 1
}  

function do_update {
	if [ "$flag_need_apt_update" == "1" ] || [ -n "$1" ]; then
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
	logexec sudo chmod +x ${program}
	
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

function logmkdir {
	dir=$1
	user=$2
	if ! [ -d "$dir" ]; then
		logexec sudo mkdir "$dir"
	fi
	if [ -n "$user" ]; then
		logexec sudo chown ${user}:${user} "$dir"
	fi
}

function textfile {
	file=$1
	contents=$2
	logmkdir $(dirname ${file})
	if [ ! -f "${file}" ]; then
		flag=1
	else
		tmpfile=$(mktemp)
		echo "$contents" > "${tmpfile}"
		if ! cmp $tmpfile $file; then
			flag=1
		fi
	fi
	if [ "$flag" == "1" ]; then
		loglog
		echo "$contents" | sudo tee "${file}" >/dev/null
	fi
}

function get_home_dir {
	echo $( getent passwd "$USER" | cut -d: -f6 )
}

function chmod_file {
	file=$1
	desired_mode=$2
	pattern='^\d+$'
	if [[ ! "${desired_mode}" =~ $pattern ]]; then
		errcho "Wrong file permissions. Needs octal format."
		exit 1
	fi
	if [ ! -f "${file}" ]; then
		errcho "File ${file} doesn't exist"
		exit 1
	fi
	actual_mode=$(stat -c "%a" ${file})
	if [ "${desired_mode}" != "${actual_mode}" ]; then
		logexec chmod ${desired_mode} ${file}
	fi
}

function smb_share_client {
	server=$1
	remote_name=$2
	local_path=$3
	credentials_file=$4
	extra_opt=$5
	if [ "${credentials_file}" == "auto" ]; then
		credentials_file="/etc/samba/user"
	fi
	if [ -n "${extra_opt}"} ]; then
		extra_opt=",${extra_opt}"
	fi
	fstab_entry ${local_path} "//${server}/${remote_name}" cifs users,credentials=${credentials_file},noexec,${extra_opt} 0 0
}

function fstab_entry {
	spec=$1
	file=$2
	vfstype=$3
	opt=$4
	dump=$5
	passno=$6
	install_apt_package augeas-tools augtool
	logheredoc EOT
	cat >/tmp/fstab.augeas<<EOT
#!/usr/bin/augtool -Asf

# The -A combined with this makes things much faster
# by loading only the required lens/file
transform Fstab.lns incl /etc/fstab
load

# $noentry will match /files/etc/fstab only if the entry isn't there yet
defvar noentry /files/etc/fstab[count(*[file="/mnt/ISO"])=0]

# Create the entry if it's missing
set $noentry/01/spec "${spec}"
set $noentry/01/file "${file}"

# Now amend existing entry or finish creating the missing one
defvar entry /files/etc/fstab/*[file="${file}"]

set $entry/spec "${spec}"
set $entry/vfstype "${vfstype}"
set $entry/opt "${opt}"
set $entry/dump "${dump}"
set $entry/passno "${passno}"
EOT
	logexec sudo /usr/bin/augtool -Asf /tmp/fstab.augeas
}

function is_host_up {
  ping -c 1 -w 1  $1 >/dev/null
}
