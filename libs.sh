#!/bin/bash 

source libapt.sh
source libfiles.sh
source libgsettings.sh
source libmount.sh
source libnet.sh


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

function make_service_user {
	local username=$1
	if ! id -u name 2>/dev/null; then
		logexec sudo useradd -r --shell /bin/false $username 
	fi
}
