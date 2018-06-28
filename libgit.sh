#!/bin/bash

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
		logexec $prefix git clone --depth 1 ${repo} ${dest}
	fi
}

