#!/bin/bash

github_token=$(openssl enc -d -in binary_blob.bin -pbkdf2 -aes-256-cbc -pass pass:BASH_REMATCH)

function get_latest_github_release_name() { #source: https://gist.github.com/lukechilds/a83e1d7127b78fef38c2914c4ececc3c
	#   set +x
	local skip_v=$2
	if ! which curl >/dev/null; then
		install_apt_package curl curl
		return 0
	fi
	ans=$(curl "$github_token" --silent "https://api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
		grep '"tag_name":' |                                            # Get tag line
	sed -E 's/.*"([^"]+)".*/\1/') # Pluck JSON value
	if [ -n "$skip_v" ]; then
		pattern='v(.*)$'
		if [[ ! "$ans" =~ $pattern ]]; then
			echo "Cannot strip \"v\" prefix from  $version"
			return 253
		else
			ans=${BASH_REMATCH[1]}
		fi
	fi
	echo "$ans"
}

function get_latest_github_tag() {
	local skip_v=$2
	local offset=$3
	if [[ "$offset" == "" ]]; then
		offset=1
	fi
	if ! which curl >/dev/null; then
		install_apt_package curl curl
		return 0
	fi
	if ! which jq >/dev/null; then
		install_apt_package jq jq
		return 0
	fi
	ans=$(curl "$github_token" --silent "https://api.github.com/repos/$1/tags" |
	jq ".[${offset}].name")
	if [ -n "$skip_v" ]; then
		pattern='v(.*).{1}$'
		if [[ ! "$ans" =~ $pattern ]]; then
			echo "Cannot strip \"v\" prefix from  $version"
			return 253
		else
			ans=${BASH_REMATCH[1]}
		fi
	fi
	echo "$ans"
}


function get_app_link_gh() {
	local name="$1" # e.g. "BurntSushi/ripgrep"
	local _arch="$2"
	local _ext="$3"
	local releases
	if [[ "${_arch}" == "" ]]; then
		_arch=$(cpu_arch)
	fi
	if [[ "${_ext}" == "" ]]; then
		_ext=".*$"
	else
		_ext="\.${_ext}$"
	fi

	releases="$(get_github_releases "$name")"

	if [[ "$_arch" == "amd64" ]]; then
		to_try=("amd64.*linux" "x86_64.*linux" "i686.*linux" "amd64" "x86_64" "i686" )
	elif [[ "$_arch" == "arm64" ]]; then
		to_try=("arm64.*linux" "arm.*linux" "arm64" "arm")
	elif [[ "$_arch" == "i386" ]]; then
		to_try=("i386.*linux" "i386")
	elif [[ "$_arch" == "none" ]]; then
		to_try=(".*")
	else
		return 0
	fi

	for phrase in "${to_try[@]}"; do
		links="$(is_arch_supported "$releases" "${phrase}.*${_ext}")"
		if [ $? == 1 ] ; then
			echo "$links" | head -n 1
			return 0
		fi
	done
	echo ""
	return 0
}


#Gets the file from latest release of github, or specific release
# example: file=$(get_latest_github_release kee-org/keepassrpc KeePassRPC.plgx)
function get_latest_github_release() {
	local local_filename="$3"
	local file
	if [ -z "$local_filename" ]; then
		local_filename="$2"
	fi
	link=$(get_latest_github_release_link "$@")
	file=$(get_cached_file "${local_filename}" "$link")
	echo "$file"
}

function get_latest_github_release_link() {
	#set -x
	local github_name="$1"
	local remote_filename="$2"
	local local_filename="$3"
	local release
	if [ -z "$remote_filename" ]; then
		return 253
	fi
	remote_filename=$(basename -- "$remote_filename") #We need only file name, no folders
	release="$4"
	if [ -z "$release" ]; then
		release=$(get_latest_github_release_name "$github_name")
	fi
	local extension="${remote_filename##*.}"
	local noextension="${remote_filename%.*}"
	if [ -z "$local_filename" ]; then
		local_filename="${noextension}-${release}.${extension}"
	fi
	echo "https://github.com/${github_name}/releases/download/${release}/${remote_filename}"
}

function make_sure_git_exists() {
	local repo_path="$1"
	local user="$2"
	if [ -z "$user" ]; then
		user="$USER"
	fi
	if [ ! -d "$repo_path" ]; then
		logmkdir "$repo_path" "$user"
	fi
	if [ ! -d "${repo_path}/.git" ]; then
		if [ "$USER" == "$user" ] && [ -w "${repo_path}" ]; then
			logexec git init "${repo_path}"
			return 0
		fi
		chown_dir "${repo_path}" "$user"
		logexec sudo --user "$user" -- git init "${repo_path}"
	fi
}

# pulls git repo as a current user $USER
function get_git_repo() {
	local repo=$1
	local dir=$2
	local name
	local user
	if [ -z ${3+x} ]; then
		name=""
	else
		name="$3"
	fi
	if [ -z ${4+x} ]; then
		user=$USER
	else
		user="$4"
	fi

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
	logmkdir "$dest" "$user"

	if [ -d "${dest}/.git" ]; then
		# update repo
		file_owner=$(stat -c '%U' "${dest}/.git")
		if [[ "${file_owner}" != "${USER}" ]]; then
			logexec sudo -u "${file_owner}" -- git pull
		else
			logexec pushd "${dest}" >/dev/null || return 1
			logexec git pull
			logexec popd >/dev/null || return 1
		fi
	else
		if [ -w "${dest}" ]; then
			logexec git clone --depth 1 --recursive "${repo}" "${dest}"
		else
			if [[ "$user" != "$USER" ]]; then
				need_root=$(sudo -u "${user}" -H sh -c "if [ -w $dest ] ; then echo 0; else; echo 1; fi")
			else
				need_root=1
			fi
			if [[ "${need_root}" == 1 ]]; then
				logexec chown "${user}" "${dest}"
			fi
			logexec sudo -u "${user}" -- git clone --depth 1 --recursive "${repo}" "${dest}"
		fi
	fi
}

function get_current_git_branch() {
	local gitpath=$1
	if [[ "$gitpath" != "" ]]; then
		if ! pushd  "$gitpath" >/dev/null; then
			errcho "Cannot change directory to $gitpath"
			return 1
		fi
	fi
	git rev-parse --abbrev-ref HEAD
	if [[ "$gitpath" != "" ]]; then
		popd >/dev/null || return 1
	fi
}
