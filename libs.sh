#!/bin/bash 

## dependency: libapt.sh
## dependency: libfiles.sh
## dependency: libgsettings.sh
## dependency: libgit.sh
## dependency: libmount.sh
## dependency: libnet.sh
## dependency: libexec.sh
## dependency: libatom.sh
## dependency: liblxc.sh
## dependency: libinstall.sh


#!/bin/bash
[[ $0 != $BASH_SOURCE ]] || echo "Script is not intended to be run, but rather sourced"

adamlibpath=$(dirname $BASH_SOURCE)


source ${adamlibpath}/libapt.sh
source ${adamlibpath}/libfiles.sh
source ${adamlibpath}/libgsettings.sh
source ${adamlibpath}/libgit.sh
source ${adamlibpath}/libmount.sh
source ${adamlibpath}/libnet.sh
source ${adamlibpath}/libexec.sh
source ${adamlibpath}/libatom.sh
source ${adamlibpath}/liblxc.sh
source ${adamlibpath}/libinstall.sh


#Gets ubuntu version in format e.g. 1804 or 1604
function get_ubuntu_version {
	local tmp=$(lsb_release -a 2>/dev/null | grep Release)
	local pattern='^Release:\s*([0-9]+)\.([0-9]+)$'
	if [[ "$tmp" =~ $pattern ]]; then
		echo ${BASH_REMATCH[1]}${BASH_REMATCH[2]}
		return 0
	fi
	local ubuntu_codename=$(get_ubuntu_codename)
	if [[ "$ubuntu_codename" == "bionic" ]]; then
		echo 1804
		return 0
	fi
	return 1
}

function get_ubuntu_codename {
	local tmp=$(lsb_release --codename 2>/dev/null | grep Codename)
	local pattern='^Codename:\s*([^ ]+)$'
	if [[ ! "$tmp" =~ $pattern ]]; then
		return 1
	fi
	local codename=${BASH_REMATCH[1]}
	if [[ "${codename}" == "tina" ]]; then
		codename=bionic
	fi 
	if [[ "${codename}" == "tara" ]]; then
		codename=bionic
	fi 
	echo "${codename}"
	return 0
}

function get_distribution {
	local tmp=$(lsb_release --id 2>/dev/null)
	local pattern='^Distributor ID:\s*([^ ]+)$'
	if [[ "$tmp" =~ $pattern ]]; then
		echo ${BASH_REMATCH[1]}
		return 0
	fi
	return 1
}


function simple_systemd_service {
	local name=$1
	local description="$2"
	local program=$3
	shift;shift;shift;shift
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
Restart=on-failure

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
Restart=on-failure

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


function custom_systemd_service {
	local name=$1
	local contents="$2"
	local is_active
	
	textfile /lib/systemd/system/${name}.service "${contents}" root
	logexec sudo systemctl daemon-reload
	is_active=$(systemctl is-active $name)
	if [ ! "$is_active" == "active" ]; then
		logexec sudo systemctl enable $name
	fi

	if ! systemctl status $name | grep -q running; then
		logexec sudo service $name start
		return 0
	fi
	return 1
}

function check_for_root {
	if which sudo >/dev/null; then
		if ! sudo -n true 2>/dev/null; then
			 errcho "User $USER doesn't have admin rights"
			 return 1
		fi
	else
		if [[ "$UID" != 0 ]]; then
			errcho "No sudo present and user $USER is not root!"
			return 1
		else
			logexec apt install sudo --yes
		fi
	fi
	return 0
}

function get_home_dir {
	if [ -n "$1" ]; then
		local USER=$1
	fi
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
		source "${HOME}/.config/user-dirs.dirs"
		varname="XDG_${dirtype}_DIR"
		echo "${!varname}"
		return
#		line=$(grep "^[^#].*${dirtype}" "${HOME}/.config/user-dirs.dirs")
#		pattern="^.*${dirtype}.*=\"?([^\"]+)\"?$"
#		if [[ "$line" =~ $pattern ]]; then
#			folder=${BASH_REMATCH[1]}
#			ans=$(echo $folder | envsubst )
#			if [ "$ans" == "$HOME" ]; then
#				ans=""
#			fi
#		fi
	fi
	echo ""
}


function make_sure_dir_is_in_a_path {
	local newpath="$1"
	
	if ! echo "$PATH" | tr ':' '\n' | grep '^\\one\\two$' >/dev/null; then
		export PATH=${PATH}:${newpath}
	fi
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

function make_service_user {
	local username=$1
	local homedir=$2
	if [ -n "$homedir" ]; then
		homedir=" --home-dir $homedir"
	fi
	if ! id -u $username 2>/dev/null; then
		logexec sudo useradd -r $homedir --shell /bin/false $username 
	fi
}


function add_group {
	local groupname=$1
	if ! grep -q "^$groupname:" /etc/group; then
		logexec sudo groupadd $groupname
	fi
}

function add_usergroup {
	local username=$1
	local groupname=$1
	if ! groups $username | grep -q "\b${groupname}\b" ;then
		logexec sudo usermod -a -G ${groupname} ${username}
	fi
}

function get_total_mem_MB {
   echo $(grep MemTotal /proc/meminfo | awk '{print $2}')/1024 | bc
}
