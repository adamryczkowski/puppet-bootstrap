#!/bin/bash

flag_need_apt_update=0

function purge_apt_package() {
	#	local ans=0
	local package=$1
	if dpkg -s "$package">/dev/null  2> /dev/null; then
		logexec sudo apt-get --yes --force-yes -q purge "$package"
		return 0
	fi
	return 0
}

function cpu_arch() {
	local arch
	arch=$(uname -m)
	if [[ "$arch" == "x86_64" ]]; then
		arch=amd64
	elif [[ "$arch" == "aarch64" ]]; then
		arch=arm64
	fi
	echo "$arch"
}

function install_apt_package() {
	#	local ans=0
	local package=$1
	local command
	if [ -z ${2+x} ]; then
		command=""
	else
		command="$2"
	fi
	if [ -n "$command" ]; then
		if ! which "$command">/dev/null  2> /dev/null; then
			do_update
			sudo apt-get --yes --force-yes -q install "$package"
			return $?
		fi
	else
		if ! dpkg -s "$package">/dev/null  2> /dev/null; then
			do_update
			sudo apt-get --yes --force-yes -q install "$package"
			return $?
		fi
		return 0
	fi
	return 0
}

function install_apt_packages() {
	#	local ans=0
	local to_install=""
	local packages=("$@")
	for package in "${packages[@]}"; do
		if ! dpkg -s "$package">/dev/null  2> /dev/null; then
			to_install="${to_install} ${package}"
		fi
	done
	if [[ "${to_install}" != "" ]]; then
		do_update || true;
		# shellcheck disable=SC2086
		logexec sudo apt-get --yes --force-yes -q  install $to_install
		return 0
	fi
}


function install_apt_package_file() {
	#	local ans=0
	local filename=$1
	local package=$2
	local source="$3"
	local cfilename
	if ! dpkg -s "$package">/dev/null  2> /dev/null; then
		if [ ! -f "${filename}" ]; then
			cfilename=$(get_cached_file "$(basename "${filename}")" "$source")
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
	return 0
}

function install_pip3_packages() {
	local to_install=""
	local packages="$*"
	for package in "${packages[@]}"; do
		if ! pip3 list | grep -qF "$package" >/dev/null  2> /dev/null; then
			to_install="${to_install} ${package}"
		fi
	done
	if [[ "${to_install}" != "" ]]; then
		do_update
		install_apt_package pipx pipx
		pipx install pipx
		pipx ensurepath
		purge_apt_package pipx
		logexec pipx install "$to_install"
		return 0
	fi
	return 0
}

# shellcheck disable=SC2120
function do_update() {
	local force_update
	if [ -z ${1+x} ]; then
		force_update=""
	else
		force_update=$1
	fi
	refresh_apt_redirections
	if [ "$flag_need_apt_update" == "1" ] || [ -n "$force_update" ]; then
		logexec sudo apt update
		flag_need_apt_update=0
		return 0
	fi
	return 0
}

function do_upgrade() {
	do_update
	logexec sudo apt upgrade --yes
	return 0
}

# example: add_ppa jtaylor/keepass
function add_ppa() {
	local the_ppa=$1

	if ! grep -q "^deb .*$the_ppa" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then

		install_apt_package software-properties-common add-apt-repository
		release=$(get_ubuntu_codename)
		if [ "$release" == "xenial" ]; then
			logexec sudo add-apt-repository -y "ppa:${the_ppa}"
		else
			if ! sudo add-apt-repository --no-update -y "ppa:${the_ppa}"; then
				logexec sudo add-apt-repository -y "ppa:${the_ppa}"
			fi
		fi
		refresh_apt_redirections
		flag_need_apt_update=1
		return 0
	fi
	return 0
}

#Adds apt source. filename must exclude the extension .list.
function add_apt_source_manual() {
	local filename="$1"
	local contents="$2"
	local release_key_URI="$3"
	local cached_release_key="$4"
	local release_key
	if textfile "/etc/apt/sources.list.d/${filename}.list" "${contents}" root; then
		flag_need_apt_update=1
		refresh_apt_redirections
	fi
	if [ -n "$release_key_URI" ]; then
		if [ -n "$cached_release_key" ]; then
			release_key=$(get_cached_file "${cached_release_key}" "${release_key_URI}")
		else
			release_key=$(get_cached_file /tmp/tmp.key "${release_key_URI}")
		fi
		fingerpr=$(get_key_fingerprint "${release_key}")

		if ! apt-key finger | grep -Eo '([0-9A-F]{4} ? ?){10}+' | sed -e "s/\([0-9A-F]\{4\}\) \([0-9A-F]\{4\}\) \([0-9A-F]\{4\}\) \([0-9A-F]\{4\}\) \([0-9A-F]\{4\}\)  \([0-9A-F]\{4\}\) \([0-9A-F]\{4\}\) \([0-9A-F]\{4\}\) \([0-9A-F]\{4\}\) \([0-9A-F]\{4\}\)/\1\2\3\4\5\6\7\8\9/g" | grep "$fingerpr" > /dev/null; then
			if [ ! -f "/etc/apt/trusted.gpg.d/${filename}.gpg" ]; then
				logexec sudo cp "${release_key}" "/etc/apt/trusted.gpg.d/${filename}.gpg"
				flag_need_apt_update=1
				sudo gpg --dearmour -o "/etc/apt/trusted.gpg.d/${filename}.gpg" < "${release_key}"
			fi
			#			logexec sudo apt-key add "${release_key}"
			# shellcheck disable=SC2024
		fi
	fi
}

function get_apt_proxy() {
	local pattern1='(#?)Acquire::http::Proxy "https?://(.*):([0-9]+)";$'
	local pattern2="^([^:]+):$pattern1"
	local myproxy
	myproxy=$(grep -rE "^$pattern1" /etc/apt/apt.conf.d | head -n 1)
	if [[ $myproxy =~ $pattern2 ]]; then
		echo "$myproxy"
		aptproxy_file=${BASH_REMATCH[1]}
		aptproxy_enabled=${BASH_REMATCH[2]}
		aptproxy_ip=${BASH_REMATCH[3]}
		aptproxy_port=${BASH_REMATCH[4]}
	else
		echo ""
	fi
}

function refresh_apt_proxy() {
	get_apt_proxy
	if ping -c 1 -w 1  "$aptproxy_ip" >/dev/null; then
		turn_http_all winehq.org
		turn_http_all nodesource.com
		turn_http_all slacktechnologies
		turn_http_all syncthing.net
		turn_http_all gitlab
		turn_http_all skype.com
		turn_http_all download.jitsi.org
		turn_http_all docker
		turn_http_all rstudio.com
		turn_http_all virtualbox.org
		turn_http_all nvidia.github.io
		turn_http_all signal.org
		turn_http_all bintray.com/zulip
		turn_http_all packagecloud.io/AtomEditor
		turn_http_all dl.bintray.com/fedarovich/qbittorrent
		turn_http_all mkvtoolnix.download
		if [ -n "$aptproxy_enabled" ]; then
			echo "Acquire::http::Proxy \"http://${aptproxy_ip}:${aptproxy_port}\";" | sudo tee "${aptproxy_file}"
		fi
	else
		if [ -z "$aptproxy_enabled" ]; then
			echo "#Acquire::http::Proxy \"http://${aptproxy_ip}:${aptproxy_port}\";" | sudo tee "${aptproxy_file}"
		fi
		turn_https_all winehq.org
		turn_https_all nodesource.com
		turn_https_all slacktechnologies
		turn_https_all syncthing.net
		turn_https_all gitlab
		turn_https_all skype.com
		turn_https_all download.jitsi.org
		turn_https_all docker
		turn_https_all rstudio.com
		turn_https_all virtualbox.org
		turn_https_all nvidia.github.io
		turn_https_all signal.org
		turn_https_all bintray.com/zulip
		turn_https_all packagecloud.io/AtomEditor
		turn_https_all dl.bintray.com/fedarovich/qbittorrent
		turn_https_all mkvtoolnix.download
	fi
}

function get_key_fingerprint() {
	local keyfile="$1"
	local fingerpr
	local pattern
	pattern='^\s*(Key fingerprint = )?([0-9A-F]{40})$'
	if [ -f "${keyfile}" ]; then
		fingerpr=$(gpg "${keyfile}" | grep -E "$pattern")
		if [[ "$fingerpr" =~ $pattern ]]; then
			fingerpr=${BASH_REMATCH[2]}
		else
			fingerpr="error"
		fi
	else
		fingerpr='missing'
	fi
	echo "${fingerpr}"
}


function find_apt_list() {
	local phrase="$1"
	files=$(shopt -s nullglob dotglob; echo /etc/apt/sources.list.d/*.list)
	if (( ${#files} )); then
		grep -l "/etc/apt/sources.list.d/*.list" -e "${phrase}"
	fi
}

function turn_https() {
	echo "http->https: $1"
	#	plik="/etc/apt/sources.list.d/$1"
	plik="$1"
	if [ -f "$plik" ]; then
		sudo sed -i 's/http:/https:/g' "${plik}*"
	fi
}

function turn_http() {
	echo "https->http: $1"
	#	plik="/etc/apt/sources.list.d/$1"
	plik="$1"
	if [ -f "${plik}" ]; then
		sudo sed -i 's/https/http/g' "${plik}*"
	fi
}

function turn_https_all() {
	find_apt_list "$1" | while read -r file; do turn_https "${file}"; done
}

function turn_http_all() {
	find_apt_list "$1" | while read -r file; do turn_http "${file}"; done
}

function refresh_apt_redirections() {
	local pattern1='(#?)Acquire::http::Proxy "https?://(.*):([0-9]+)";$'
	local pattern2="^([^:]+):$pattern1"
	if ! myproxy=$(grep -rE "^$pattern1" /etc/apt/apt.conf.d | head -n 1); then
		myproxy=""
	fi
	if [[ $myproxy =~ $pattern2 ]]; then
		aptproxy_file=${BASH_REMATCH[1]}
		aptproxy_enabled=${BASH_REMATCH[2]}
		aptproxy_ip=${BASH_REMATCH[3]}
		aptproxy_port=${BASH_REMATCH[4]}
		echo "Found aptproxy: ${aptproxy_ip}:${aptproxy_port} in ${aptproxy_file}"
		if ping -c 1 -w 1  "$aptproxy_ip" >/dev/null; then
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
				echo "Acquire::http::Proxy \"http://${aptproxy_ip}:${aptproxy_port}\";" | sudo tee "${aptproxy_file}"
			fi
		else
			if [ -z "$aptproxy_enabled" ]; then
				echo "#Acquire::http::Proxy \"http://${aptproxy_ip}:${aptproxy_port}\";" | sudo tee "${aptproxy_file}"
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
