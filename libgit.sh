#!/bin/bash

github_token=$(openssl enc -d -in binary_blob.bin -pbkdf2 -aes-256-cbc -pass pass:BASH_REMATCH)

function get_latest_github_release_name { #source: https://gist.github.com/lukechilds/a83e1d7127b78fef38c2914c4ececc3c
#   set +x
	local skip_v=$2
#	install_apt_package curl curl
	ans=$(curl $github_token --silent "https://api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
		grep '"tag_name":' |                                            # Get tag line
		sed -E 's/.*"([^"]+)".*/\1/') # Pluck JSON value
	if [ -n "$skip_v" ]; then
		pattern='v(.*)$'
		if [[ ! "$ans" =~ $pattern ]]; then
			echo "Cannot strip \"v\" prefix from  $version"
			return -1 
		else
			ans=${BASH_REMATCH[1]}
		fi
	fi
	echo "$ans"
}

#Gets the file from latest release of github, or specific release
# example: file=$(get_latest_github_release kee-org/keepassrpc KeePassRPC.plgx)
function get_latest_github_release {
	local local_filename="$3"
	if [ -z "$local_filename" ]; then
		local_filename="$2"
	fi
	link=$(get_latest_github_release_link "$@")
	local file=$(get_cached_file "${local_filename}" "$link")
	echo "$file"	
}

function get_latest_github_release_link {
#set -x
	local github_name="$1"
	local remote_filename="$2"
	local local_filename="$3"
	if [ -z "$remote_filename" ]; then
		return -1
	fi
	remote_filename=$(basename -- "$remote_filename") #We need only file name, no folders
	local release="$4"
	if [ -z "$release" ]; then
		local release=$(get_latest_github_release_name $github_name)
	fi
	local extension="${remote_filename##*.}"
	local noextension="${remote_filename%.*}"
	if [ -z "$local_filename" ]; then
		local_filename="${noextension}-${release}.${extension}"
	fi
	echo "https://github.com/${github_name}/releases/download/${release}/${remote_filename}"
}

function make_sure_git_exists {
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
		logexec $prefix git clone --depth 1 --recursive ${repo} ${dest}
	fi
}

