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

		logexec sudo add-apt-repository -y ppa:${the_ppa}
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

function add_host {
	host=$1
	ip=$2
	
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
		logexec sudo mkdir -p "$dir"
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

function install_script {
	local input_file="$1"
	local dest="$2"
	local user=$3
	if [ -z ${user} ]; then
		user=auto
	fi
	if [ ! -f "${input_file}" ]; then
		errcho "Cannot find ${input_file}"
		exit 1
	fi
	if [ -z "$dest" ]; then
		dest=/usr/local/bin
	fi
	if [ -d "$dest" ]; then
		dest="${dest}/$(basename "$input_file")"
	fi
	if [ -f "$dest" ]; then
		if ! cmp "$dest" "$input_file"; then
			if [ -w "$dest" ]; then
				logexec cp "$input_file" "$dest"
			else
				logexec sudo cp "$input_file" "$dest"
			fi
		fi
	fi
	if [ ! -f "$dest" ]; then
		if [ -w "$dest" ]; then
			logexec cp "$input_file" "$dest"
		else
			logexec sudo cp "$input_file" "$dest"
		fi
	fi
	if [ ! -f "$dest" ]; then
		errcho "Error when copying ${input_file} into ${dest}"
		exit 1
	fi
	if [ $user != "auto" ]; then
		cur_owner="$(stat --format '%U' "$dest")"
		if [ "$user" != "$cur_owner" ]; then
			if [ -w "$dest" ]; then
				logexec chown $user "$dest"
			else
				logexec sudo chown $user "$dest"
			fi
		fi
	fi
	if [[ ! -x "$dest" ]]; then
		if [ -w "$dest" ]; then
			logexec chmod +x "$dest"
		else
			logexec sudo chmod +x "$dest"
		fi
	fi
	if [[ ! -x "$dest" ]]; then
		errcho "Cannot set executable permission to $dest"
		exit 1
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
	if [ -n "${extra_opt}" ]; then
		extra_opt=",${extra_opt}"
	fi
	fstab_entry "//${server}/${remote_name}" ${local_path} cifs users,credentials=${credentials_file},noexec${extra_opt} 0 0
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
defvar noentry /files/etc/fstab[count(*[file="${file}"])=0]

# Create the entry if it's missing
set \$noentry/01/spec "${spec}"
set \$noentry/01/file "${file}"

# Now amend existing entry or finish creating the missing one
defvar entry /files/etc/fstab/*[file="${file}"]

set \$entry/spec "${spec}"
set \$entry/vfstype "${vfstype}"
rm \$entry/opt

EOT
	OLDIFS="$IFS"
	export IFS=","
	local i=1
	pattern='^([^=]+)=(.*)$'
	for entry in $opt; do
		if [ "$i" == "1" ]; then
			echo "ins opt after \$entry/vfstype">>/tmp/fstab.augeas
		else
			echo "ins opt after \$entry/opt[last()]">>/tmp/fstab.augeas
		fi
		if [[ "${entry}" =~ $pattern ]]; then
			lhs=${BASH_REMATCH[1]}
			rhs=${BASH_REMATCH[2]}
			echo "set \$entry/opt[last()] \"$lhs\"">>/tmp/fstab.augeas
			echo "set \$entry/opt[last()]/value \"${rhs}\"">>/tmp/fstab.augeas
		else
			echo "set \$entry/opt[last()] \"$entry\"">>/tmp/fstab.augeas
		fi
		let "i=i+1"
	done
	export IFS="$OLDIFS"
	echo "set \$entry/dump \"${dump}\"">>/tmp/fstab.augeas
	echo "set \$entry/passno \"${passno}\"">>/tmp/fstab.augeas
	logexec sudo /usr/bin/augtool -Asf /tmp/fstab.augeas
	
}

function is_host_up {
	ping -c 1 -w 1  $1 >/dev/null
}

function get_ui_context {
	if [ -z "${DBUS_SESSION_BUS_ADDRESS}" ]; then
		compatiblePrograms=( nemo unity nautilus kdeinit kded4 pulseaudio trackerd )
		for index in ${compatiblePrograms[@]}; do
			PID=$(pidof -s ${index})
			if [[ "${PID}" != "" ]]; then
				break
			fi
		done
		if [[ "${PID}" == "" ]]; then
			ercho "Could not detect active login session"
			return 1
		fi
	
		QUERY_ENVIRON="$(tr '\0' '\n' < /proc/${PID}/environ | grep "DBUS_SESSION_BUS_ADDRESS" | cut -d "=" -f 2-)"
		if [[ "${QUERY_ENVIRON}" != "" ]]; then
			export DBUS_SESSION_BUS_ADDRESS="${QUERY_ENVIRON}"
			echo "Connected to session:"
			echo "DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS}"
		else
			echo "Could not find dbus session ID in user environment."
			return 1
		fi
	fi
	export DISPLAY=:0
	return 0
}

function gsettings_set_value {
	schema=$1
	name=$2
	value=$3
	get_ui_context
	existing_value=$(gsettings get ${schema} ${name})
	if [ "$existing_value" != "$value" ]; then
		logexec gsettings set ${schema} ${name} ${value}
	fi
}

function set_mime_default {
	filetype=$1
	value=$2
	get_ui_context
	existing_value=$(xdg-mime query default ${filetype})
	if [ "$existing_value" != "$value" ]; then
		logexec xdg-mime default ${value} ${filetype}
	fi
}

function gsettings_add_to_array {
	schema=$1
	name=$2
	value=$3
	get_ui_context
	existing_value=$(gsettings get ${schema} ${name})
	if [ "$existing_value" != "$value" ]; then
		logexec gsettings set ${schema} ${name} ${value}
	fi
}

function gsettings_remove_from_array {
	local schema=$1
	local name=$2
	local value=$3
	get_ui_context
	local existing_values=$(gsettings get ${schema} ${name})
	local change=0
	if [ -n "${existing_values}" ]; then
		local newvalue="['"
		local flag=0
		local oldifs=${IFS}
		export IFS="', '"
		for item in $existing_values; do
			if [[ "$item" != "" && "$item" != "[" && "$item" != "]" ]]; then
				if [ "${item}" != "${value}" ]; then
					if [ "${flag}" == "1" ]; then
						newvalue="${newvalue}', '${item}"
					else
						newvalue="${newvalue}${item}"
						flag=1
					fi
				else
					change=1
				fi
			fi
		done
		newvalue="${newvalue}']"
		export IFS=${oldifs}
	fi
	if [ "$change" == "1" ]; then
		echo "gsettings set ${schema} ${name} ${newvalue}"
		gsettings set ${schema} ${name} "${newvalue}"
	fi
}

function get_git_repo {
	local repo=$1
	local dir=$2
	local name=$3
	if [ -z "${name}" ]; then
		local pattern='^.*/([^/]+)(\.git)$'
		if [[ "$repo" =~ $pattern ]]; then
			name=${BASH_REMATCH[1]}
		else
			local pattern='^.*/([^/]+)$'
			if [[ "$repo" =~ $pattern ]]; then
				name=${BASH_REMATCH[1]}
			else
				errcho "${repo} has wrong format"
			fi
		fi
	fi
	local dest=${dir}/${name}
	install_apt_package git
	if [ -d "$dir" ]; then
		errcho "Cannot find ${dir} directory to clone git repo ${repo}"
		exit 1
	fi
	if [ -w "$dir" ]; then
		local prefix=""
	else
		local prefix="sudo "
	fi
	
	if [ -d ${dest} ]; then
		# update repo
		logexec $prefix git pull
	else
		# clone repo
		logexec $prefix git clone --depth 1 ${repo} ${dest}
	fi
}
