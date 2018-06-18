#!/bin/bash 


function purge_apt_package {
	local ans=0
	local package=$1
	if dpkg -s "$package">/dev/null  2> /dev/null; then
		logexec sudo apt-get --yes --force-yes -q purge "$package"
		return 0
	fi
	return 1
}

function install_apt_package {
	local ans=0
	local package=$1
	local command=$2
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
	local ans=0
	local to_install=""
	local packages="$@"
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

function calcshasum {
	file="$1"
	if [ -f "$file" ]; then 
		local shasum=$(shasum "$file")
		local pattern='^([^ ]+) '
		if [[ "$shasum" =~ $pattern ]]; then
			shasum=${BASH_REMATCH[1]}
		else
			errcho "Wrong shasum format"
		fi
	else
		shasum=""
	fi
	echo $shasum
}

function apply_patch {
	local file="$1"
	local hash_orig="$2"
	local hash_dest="$3"
	local patchfile="$4"
	if [[ -f "$file" ]] && [[ -f "$patchfile" ]]; then
		local shasum=$(calcshasum "$file")
		if [[ "$shasum"=="$hash_orig" ]]; then
			if patch --dry-run "$file" "$patchfile" >/dev/null; then
				if [ -w "$file" ]; then
					logexec patch "$file" "$patchfile"
				else
					logexec sudo patch "$file" "$patchfile"
				fi
			else
				errcho "Error while applying the patch"
			fi
		elif [[ "$(shasum "$file")"=="$hash_dest" ]]; then
			#Do nothing. Work is already done
			return 0
		else
			errcho "Wrong contents of the $file. Expected hash $hash_orig."
			return 1
		fi
	else
		errcho "Missing $file"
		return 1
	fi
}

#Gets ubuntu version in format e.g. 1804 or 1604
function get_ubuntu_version {
	local tmp=$(lsb_release -a 2>/dev/null | grep Release)
	local pattern='^Release:\s*([0-9]+)\.([0-9]+)$'
	if [[ "$tmp" =~ $pattern ]]; then
		echo ${BASH_REMATCH[1]}${BASH_REMATCH[2]}
		return 0
	fi
	return 1
}

function get_ubuntu_codename {
	local tmp=$(lsb_release --codename 2>/dev/null | grep Codename)
	local pattern='^Codename:\s*([^ ]+)$'
	if [[ "$tmp" =~ $pattern ]]; then
		echo ${BASH_REMATCH[1]}
		return 0
	fi
	return 1
}

function install_apt_package_file {
	local ans=0
	local filename=$1
	local package=$2
	local source="$3"
	if ! dpkg -s "$package">/dev/null  2> /dev/null; then
		local tmp=$(dirname ${filename})
		if [ "${tmp}" == "." ]; then
			local cfilename=$(get_cached_file "${filename}" "$source")
			if [ ! -f "${cfilename}" ]; then
				errcho "Cannot find ${filename}"
				return 255
			fi
			filename="${cfilename}"
		fi 
		logexec sudo gdebi "$filename" --n
		return 0
	fi
	return 1
}

function install_pip3_packages {
	local ans=0
	local to_install=""
	local packages="$@"
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
	local the_ppa=$1
	
	if ! grep -q "^deb .*$the_ppa" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then

		install_apt_package software-properties-common add-apt-repository

		logexec sudo add-apt-repository -y ppa:${the_ppa}
		flag_need_apt_update=1
		return 0
	fi
	return 1
}

#Adds apt source. filename must exclude the extension .list. 
function add_apt_source_manual {
	local filename="$1"
	local contents="$2"
	local release_key_URI="$3"
	local cached_release_key="$4"
	local release_key
	textfile "/etc/apt/sources.list.d/${filename}.list" "${contents}"
	if [ "$?" == "0" ]; then
		flag_need_apt_update=1
	fi
	if [ -n "$release_key_URI" ]; then
		if [ -n "$cached_release_key" ]; then
			release_key=$(get_cached_file "${cached_release_key}" "${release_key_URI}")
		else
			release_key=$(get_cached_file /tmp/tmp.key "${release_key_URI}")
		fi
		fingerpr=$(get_key_fingerprint)
		if ! apt-key finger | grep "$fingerpr" > /dev/null; then
			logexec sudo apt-key add "${release_key}"
		fi
	fi
}

function get_key_fingerprint {
	local keyfile="$1"
	local fingerpr
	local pattern
	if [ -f "${keyfile}" ]; then
		fingerpr=$(cat "${keyfile}" | gpg --with-fingerprint | grep "Key fingerprint")
		pattern='^\s*Key fingerprint = ([0-9A-F]{4} [0-9A-F]{4} [0-9A-F]{4} [0-9A-F]{4} [0-9A-F]{4}  [0-9A-F]{4} [0-9A-F]{4} [0-9A-F]{4} [0-9A-F]{4} [0-9A-F]{4})$'
		if [[ "$fingerpr" =~ $pattern ]]; then
			fingerpr=${BASH_REMATCH[1]}
		else
			fingerpr="error"
		fi
	else
		fingerpr='missing'
	fi
	echo "${fingerpr}"
}

function edit_bash_augeas {
	local file=$1
	local var=$2
	local value=$3
	install_apt_package augeas-tools augtool
	local oldvalue=$(sudo augtool -L -A --transform "Shellvars incl $file" get "/files${file}/${var}" | sed -En 's/\/.* = \"?([^\"]*)\"?$/\1/p')
	if [ "$value" != "$oldvalue" ]; then
		logexec sudo augtool -L -A --transform "Shellvars incl $file" set "/files${file}/${var}" "${value}" >/dev/null
	fi
}

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

function simple_systemd_service {
	local name=$1
	local description="$2"
	local program=$3
	shift;shift;shift
	local args="$@"
	local is_active
	
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

function get_iface_ip {
	local iface=$1
	if ifconfig $local_n2n_iface 2>/dev/null >/dev/null; then
		ip addr show $1 | awk '$1 == "inet" {gsub(/\/.*$/, "", $2); print $2}'
		return 0
	else
		return 1
	fi

}

function logmkdir {
	local dir=$1
	local user=$2
	if ! [ -d "$dir" ]; then
		logexec sudo mkdir -p "$dir"
	fi
	if [ -n "$user" ]; then
		logexec sudo chown ${user}:${user} "$dir"
	fi
}

function linetextfile {
	local file="$1"
	local line="$2"
	if ! grep -qF -- "$line" "$file"; then
		if [ -w "$file" ]; then
			$loglog
			echo "$line" >> "$file"
		else
			$loglog
			echo "$line" | sudo tee -a "$file"
		fi
	fi
}

function textfile {
	local file=$1
	local contents=$2
	local flag
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
		if [ -w "${file}" ]; then
			loglog
			echo "$contents" | tee "${file}" >/dev/null
		else
			loglog
			echo "$contents" | sudo tee "${file}" >/dev/null
		fi
		return 0
	fi
	return 1
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
		return 1
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
		return 1
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
		return 1
	fi
}

function get_home_dir {
	local USER=$1
	echo $( getent passwd "$USER" | cut -d: -f6 )
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


function chmod_file {
	local file=$1
	local desired_mode=$2
	local pattern='^\d+$'
	local actual_mode
	if [[ ! "${desired_mode}" =~ $pattern ]]; then
		errcho "Wrong file permissions. Needs octal format."
		return 1
	fi
	if [ ! -f "${file}" ]; then
		errcho "File ${file} doesn't exist"
		return 1
	fi
	actual_mode=$(stat -c "%a" ${file})
	if [ "${desired_mode}" != "${actual_mode}" ]; then
		logexec chmod ${desired_mode} ${file}
	fi
}

function smb_share_client {
	local server=$1
	local remote_name=$2
	local local_path=$3
	local credentials_file=$4
	local extra_opt=$5
	if [ "${credentials_file}" == "auto" ]; then
		credentials_file="/etc/samba/user"
	fi
	if [ -n "${extra_opt}" ]; then
		extra_opt=",${extra_opt}"
	fi
	fstab_entry "//${server}/${remote_name}" ${local_path} cifs users,credentials=${credentials_file},noexec,noauto${extra_opt} 0 0
}

function mount_smb_share {
	local mountpoint=$1
	if [ ! -d "$mountpoint" ]; then
		while [ ! -d "$mountpoint" ]; do
			mountpoint=$(dirname "$mountpoint")
		done
		logexec mount "$mountpoint"
	fi
}

function fstab_entry {
	local spec=$1
	local file=$2
	local vfstype=$3
	local opt=$4
	local dump=$5
	local passno=$6
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
	local user=$1
	if [ -z "$user" ]; then
		user=$USER
	fi
	if [ -z "${DBUS_SESSION_BUS_ADDRESS}" ]; then
		compatiblePrograms=( nemo unity nautilus kdeinit kded4 pulseaudio trackerd )
		for index in ${compatiblePrograms[@]}; do
			PIDS=$(pidof -s ${index})
			if [[ "${PIDS}" != "" ]]; then
				for PID in ${PIDS[@]}; do
					uid=$(awk '/^Uid:/{print $2}' /proc/${PID}/status)
					piduser=$(getent passwd "$uid" | awk -F: '{print $1}')
					if [[ "$piduser" == ${user} ]]; then
						break;
					fi
				done
			fi
		done
		if [[ "${PID}" == "" ]]; then
			ercho "Could not detect active login session"
			return 1
		fi
		if [ -r /proc/${PID}/environ ]; then
			QUERY_ENVIRON="$(cat /proc/${PID}/environ | tr '\0' '\n' | grep "DBUS_SESSION_BUS_ADDRESS" | cut -d "=" -f 2-)"
		else
			QUERY_ENVIRON="$(sudo cat /proc/${PID}/environ | tr '\0' '\n' | grep "DBUS_SESSION_BUS_ADDRESS" | cut -d "=" -f 2-)"
		fi
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
	local schema=$1
	local name=$2
	local value=$3
	get_ui_context
	existing_value=$(gsettings get ${schema} ${name})
	if [ "$existing_value" != "$value" ]; then
		logexec gsettings set ${schema} ${name} ${value}
	fi
}

function set_mime_default {
	local filetype=$1
	local value=$2
	get_ui_context
	existing_value=$(xdg-mime query default ${filetype})
	if [ "$existing_value" != "$value" ]; then
		logexec xdg-mime default ${value} ${filetype}
	fi
}

function load_gsettings_array {
	local schema=$1
	local name=$2
	get_ui_context
	local existing_values=$(gsettings get ${schema} ${name})
	if [ -n "${existing_values}" ]; then
		local new_array=()
		local flag=0
		local oldifs=${IFS}
		export IFS="', '"
		for item in $existing_values; do
			if [[ "$item" != "" && "$item" != "[" && "$item" != "]" ]]; then
				new_array+=($item)
			fi
		done
		export IFS=${oldifs}
	fi
	(>&2 echo "Number of elements of new_array: ${#new_array[@]}")
	declare -p new_array | sed -e 's/^declare -a new_array=//'
}

function remove_item_from_array {
	get_ui_context
	eval "local -a input_array=$1"
	(>&2 echo "Number of elements of array: ${#input_array[@]}")
	local target=$2
	local -a output_array=()
	for value in "${input_array[@]}"; do
		if [[ $value != $target ]]; then
			output_array+=($value)
		fi
	done
	(>&2 echo "Number of elements of output_array: ${#output_array[@]}")
	declare -p output_array | sed -e 's/^declare -a output_array=//'
}

function find_item_in_array {
	get_ui_context
	eval "local -a array=$1"
	(>&2 echo "Number of elements of array: ${#array[@]}")
	local match="$2"
	local i=1
	for item in "${array[@]}"; do
		if [ "$item" == "$match" ]; then
			echo $i
			return 0
		fi
	done
	echo 0
	return 0
}

function add_item_to_array {
	get_ui_context
	eval "local -a array=$1"
	(>&2 echo "Number of elements of array: ${#array[@]}")
	local target=$2
	local position=$3
	
	index=$(find_item_in_array "$1" "$2")
	
	if [ "$index" != "0" ]; then
		if [ -n "${position}" ]; then
			if [ "$position" == "$index" ]; then
				return 0 #Element already present
			fi
		else
			if [ "$position" == "${#array[@]}" ]; then
				return 0 #Element already present
			fi
		fi
		eval "local -a array=$(remove_item_from_array "$1" "$2")"
		(>&2 echo "Number of elements of array: ${#array[@]}")
	fi
	if [ -n "${position}" ]; then
		local new_array=( "${array[@]:0:${position}}" "${target}" "${array[@]:${position}}" )
		declare -p new_array | sed -e 's/^declare -a new_array=//'
	else
		array+=($target)
		declare -p array | sed -e 's/^declare -a array=//'
		(>&2 echo "Number of elements of array: ${#array[@]}")
	fi
}

function set_gsettings_array {
	get_ui_context
	local schema=$1
	local name=$2
	local value_arr_str="$3"
	local i=1
	local old_value_str="$(load_gsettings_array ${schema} ${name})"
	if [ "$old_value_str" == "$value_arr_str" ]; then
		return 0 #nothing to do
	fi
	eval "local -a value_array=$3"
	(>&2 echo "Number of elements of value_array: ${#value_array[@]}")
	local ans="['"
	for value in "${value_array[@]}"; do
		if [ "$i" == "1" ]; then
			ans="${ans}${value}"
		else
			ans="${ans}', '${value}"
		fi 
		((i++))
	done
	ans="${ans}']"
	gsettings set ${schema} ${name} "${ans}"
}

function gsettings_add_to_array {
	local schema=$1
	local name=$2
	local value=$3
	local position=$4
	
	local existing_values_str=$(load_gsettings_array ${schema} ${name})
	
	local ans_str=$(add_item_to_array "${existing_values_str}" ${value} ${position})
	set_gsettings_array ${schema} ${name} "${ans_str}"
}

function gsettings_remove_from_array {
	local schema=$1
	local name=$2
	local value=$3
	
	local existing_values_str=$(load_gsettings_array ${schema} ${name})
	
	local ans_str=$(remove_item_from_array "${existing_values_str}" "${value}")
	set_gsettings_array ${schema} ${name} "${ans_str}"
}

function gsettings_remove_from_array2 {
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
	if [ ! -d "$dir" ]; then
		errcho "Cannot find ${dir} directory to clone git repo ${repo}"
		return 1
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

function make_desktop_non_script {
	local execpath="$1"
	local title="$2"
	local description="$3"
	local icon="$4"
	
	if [ -f "$icon" ]; then
		icon_dir="/usr/share/icons/myicon"
		cp_file "$icon" "${icon_dir}/" root
		icon="$(basename "$icon")"
	fi
	
	contents="
[Desktop Entry]
Version=1.0
Name=${title}
Comment=${description}
Exec=${execpath}
Icon=${icon}
Terminal=false
Type=Application
Categories=Application;"
	filename=$(echo "$execpath" | awk '{print $1;}')
	textfile "/usr/share/applications/${filename}.desktop" "$contents"
}

# returns path
function get_cached_file {
	local filename="$1"
	local download_link="$2"
	if [ -d "${repo_path}" ]; then
		if [ ! -w "${repo_path}" ]; then
			errcho "Cannot write to the repo"
			local repo_path="/tmp/repo_path"
			mkdir -p /tmp/repo_path
		fi
	else
		mkdir -p /tmp/repo_path
		local repo_path="/tmp/repo_path"
	fi
	if [ ! -f "${repo_path}/${filename}" ]; then
		wget -c "${download_link}" -O "${repo_path}/${filename}"
	fi
	if [ ! -f "${repo_path}/${filename}" ]; then
		errcho "Cannot download the file"
		return 1
	fi
	echo "${repo_path}/${filename}"
}

function cp_file {
	local source="$1"
	local dest="$2"
	local user="$3"
	if [ -z "$user" ]; then
		errcho "No username!"
	fi
	i=$((${#dest}-1))
	last="${dest:$i:1}"
	if [ "$last" == "/" ]; then
		destdir="${dest:0:$i}"
		destfile="$(basename $source)"
	else
		destdir="$(dirname $dest)"
		destfile="$(basename $dest)"
	fi
	if [ ! -d "$destdir" ]; then
		logmkdir "$destdir" "$user"
	fi
	if [ -w "$destdir" ]; then
		local prefix=""
	else
		local prefix="sudo"
	fi
	if [ ! -f "${destdir}/${destfile}" ]; then
		logexec ${prefix} cp "${source}" "${dest}"
	fi
	owner=$(stat -c '%U' "${destdir}/${destfile}")
	if [ "$owner" != "$user" ]; then
		logexec chmod -R "${user}" "${destdir}/${destfile}"
	fi
}

#Iterates over all devices managed by dmsetup and returns true, if found the device with the given path
function find_device_in_dmapper {
	local target="$1"
	local pattern1='^([^ ]+ +)'
	local pattern2='device: *()[^ ]+)$'
	local line
	local device
	local backend
	sudo dmsetup ls | while read line; do
		if [[ "$line" =~ $pattern1 ]]; then
			device=${BASH_REMATCH[1]}
			backend=$(sudo cryptsetup status $device | grep -F "device:")
			if [[ "${backend}" =~ $pattern2 ]]; then
				device=${BASH_REMATCH[1]}
				if [ "$device" == "$target" ]; then
					echo "$device"
					return 0
				fi
			fi
		else
			errcho "Syntax error of the output of dmsetup."
		fi
	done
	return -1 #not found
}

function is_mounted {
	local device=$1
	local mountpoint=$2
	if [ -n "$device" ] && [ -n "$mountpoint" ]; then
		ans=$(mount | grep -F "${device} on ${mountpoint}")
	elif [ -n "$device" ]; then
		ans=$(mount | grep -F "${device} on ")
	elif [ -n "$mountpoint" ]; then
		ans=$(mount | grep -F " on ${mountpoint}")
	else
		errcho "is_mounted called with no arguments"
		return -1
	fi
	if [ "$ans" != "" ]; then
		return 0
	else
		return -1
	fi
}

function find_device_from_mountpoint {
	local mountpoint="$1"
	local pattern="^(.*) on (${mountpoint}) type "
	local ans
	ans=$(mount | grep -E " on ${mountpoint} ")
	if [[ "$ans" =~ $pattern ]]; then
		echo "${BASH_REMATCH[1]}"
		return 0
	fi
	return -1
}

#Gets the backing device from the dm device if it uses cryptsetup
function device_from_crypt_dmapper {
	local dmdevice=$1
	local pattern='device: *([^ ]+)$'
	local backend_line=$(sudo cryptsetup status "/dev/mapper/${dmdevice}" | grep -F "device:")
	if [[ "$backend_line" =~ $pattern ]]; then
		echo "${BASH_REMATCH[1]}"
		return 0
	else
		echo ""
		return -1
	fi
}

function backing_luks_device_from_mount_point {
	local mountpoint="$1"
	local pattern='^/dev/mapper/(.*)$'
	local actual_dmdevice=$(find_device_from_mountpoint "${mount_point}")
	if [ -n "${actual_dmdevice}" ]; then
		if [[ "$actual_dmdevice" =~ $pattern ]]; then
			local actual_dmdevice="${BASH_REMATCH[1]}"
			local actual_device=device_from_crypt_dmapper ${actual_dmdevice}
			if [ -n "${actual_device}" ]; then
				echo "$actual_device"
				return 0
			else
				errcho "The device mounted under ${mount_point} is not Luks. Exiting."
				return 3
			fi
		else
			errcho "Something else is mounted under ${mount_point}. Exiting."
			return 2
		fi
	else
		errcho "Mount point not found. Exiting."
		return 1
	fi
}
