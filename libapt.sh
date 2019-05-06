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
	for package in ${packages[@]}; do
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


function install_apt_package_file {
	local ans=0
	local filename=$1
	local package=$2
	local source="$3"
	if ! dpkg -s "$package">/dev/null  2> /dev/null; then
		if [ ! -f "${filename}" ]; then
			local cfilename=$(get_cached_file $(basename ${filename}) "$source")
			if [ ! -f "${cfilename}" ]; then
				errcho "Cannot find ${filename}"
				return 255
			fi
			filename="${cfilename}"
		fi 
		logexec sudo dpkg -i "$filename"
		logexec sudo apt install -f --yes
		return 0
	fi
	return 1
}

function install_pip3_packages {
	local ans=0
	local to_install=""
	local packages="$@"
	for package in ${packages[@]}; do
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
	refresh_apt_redirections
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

# example: add_ppa jtaylor/keepass
function add_ppa {
	local the_ppa=$1
	
	if ! grep -q "^deb .*$the_ppa" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then

		install_apt_package software-properties-common add-apt-repository
		release=$(get_ubuntu_codename)
		if [ "$release" == "xenial" ]; then
			logexec sudo add-apt-repository -y ppa:${the_ppa}
		else
			if ! logexec sudo add-apt-repository --no-update -y ppa:${the_ppa} then
				logexec sudo add-apt-repository -y ppa:${the_ppa}
			fi
		fi
		refresh_apt_redirections
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
	textfile "/etc/apt/sources.list.d/${filename}.list" "${contents}" root
	if [ "$?" == "0" ]; then
		flag_need_apt_update=1
		refresh_apt_redirections
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




function find_apt_list {
	phrase="$1"
	if [[ -f /etc/apt/sources.list.d/*.list ]]; then
		grep -l /etc/apt/sources.list.d/*.list -e "${phrase}"
	fi
}

function turn_https {
	echo "http->https: $1"
#	plik="/etc/apt/sources.list.d/$1"
	plik="$1"
	if [ -f "$plik" ]; then
		sudo sed -i 's/http:/https:/g' ${plik}*
	fi
}

function turn_http {
	echo "https->http: $1"
#	plik="/etc/apt/sources.list.d/$1"
	plik="$1"
	if [ -f "${plik}" ]; then
		sudo sed -i 's/https/http/g' ${plik}*
	fi
}

function turn_https_all {
	find_apt_list "$1" | while read file; do turn_https ${file}; done
}

function turn_http_all {
	find_apt_list "$1" | while read file; do turn_http ${file}; done
}

function refresh_apt_redirections {
	pattern1='(#?)Acquire::http::Proxy "https?://(.*):([0-9]+)";$'
	pattern2="^([^:]+):$pattern1"
	myproxy=$(grep -rE "^$pattern1" /etc/apt/apt.conf.d | head -n 1)
	if [[ $myproxy =~ $pattern2 ]]; then
		aptproxy_file=${BASH_REMATCH[1]}
		aptproxy_enabled=${BASH_REMATCH[2]}
		aptproxy_ip=${BASH_REMATCH[3]}
		aptproxy_port=${BASH_REMATCH[4]}
		echo "Found aptproxy: ${aptproxy_ip}:${aptproxy_port} in ${aptproxy_file}"
		if ping -c 1 -w 1  $aptproxy_ip >/dev/null; then
			turn_http_all winehq.org
			turn_http_all nodesource.com
			turn_http_all slacktechnologies
			turn_http_all syncthing.net
			turn_http_all gitlab
			turn_http_all skype.com
			turn_http_all docker
			turn_http_all rstudio.com
			turn_http_all virtualbox.org
			turn_http_all signal.org
			turn_http_all bintray.com/zulip
			if [ -n "$aptproxy_enabled" ]; then
				echo "Acquire::http::Proxy \"http://${aptproxy_ip}:${aptproxy_port}\";" | sudo tee ${aptproxy_file}
			fi
		else
			if [ -z "$aptproxy_enabled" ]; then
				echo "#Acquire::http::Proxy \"http://${aptproxy_ip}:${aptproxy_port}\";" | sudo tee ${aptproxy_file}
			fi
			turn_https_all winehq.org
			turn_https_all nodesource.com
			turn_https_all slacktechnologies
			turn_https_all syncthing.net
			turn_https_all gitlab
			turn_https_all skype.com
			turn_https_all docker
			turn_https_all rstudio.com
			turn_https_all virtualbox.org
			turn_https_all signal.org
			turn_https_all bintray.com/zulip
		fi
	fi
}
