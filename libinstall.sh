#!/bin/bash 

function errcho {
	echo "ERROR: $@"
}

function logexec {
 $@
}

function get_app_version {
	local app="$1" # name/path to the app
	if [ "$2" == "" ]; then
		local app_arg="--version"
	else
		local app_arg="$2" # e.g. "--version"
	fi
	if which "$app" >/dev/null; then
		ans=$("$app" "$app_arg" | head)
	elif [ -f "$app" ]; then
		ans=$("$app" "$app_arg")
	else
		echo ""
		return 0
	fi
	pattern='([[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+)'
	if [[ "$ans" =~ $pattern ]]; then
		echo ${BASH_REMATCH[1]}
	else 
		echo ""
	fi 
}


function get_github_releases {
	local name="$1" # e.g. "BurntSushi/ripgrep"
	curl -s https://api.github.com/repos/$1/releases/latest | jq -r ".assets[] | select(.name | contains(\"\")) | .browser_download_url"
}

function install_update_hook {
	local gh_name="$1"
	local asset_path="$2"
	local asset_type="$3" # 'source' or 'deb' or 'binary' or 'git'
	local version="$4"
	local update_script_text="$5"
	local cache_filename="$6"
	local timestamp=$(date)
	
	local updater_path=/usr/local/lib/adam/updater/records
	
	if [[ "$gh_name" == "" ]]; then
		pattern="([^/]+)/([^/]+)"
		if [[ "$gh_name" =~ $pattern ]]; then
			app_name=${BASH_REMATCH[2]}
			user_name=${BASH_REMATCH[1]}
		else
			errcho "Cannot parse github name. Must be in format <user>/<repo>"
			return 1
		fi
	fi
	
	if [[ "$asset_path" == "" ]]; then
		errcho "Asset_path cannot be empty"
		return 1
	fi
	
	if [[ "$asset_type" != "source" && "$asset_type" != "deb" && "$asset_type" != "binary" && "$asset_type" != "git" ]]; then
		errcho "Asset_type must be 'source', 'deb', 'binary' or 'git'"
		return 1
	fi
	
	if [[ "$version" == "" ]]; then
		errcho "Version must not be empty"
		return 1
	fi

	logmkdir ${updater_path}
	
	if [[ "$update_script_text" == "" ]]; then
		sudo rm "${updater_path}/${script_filename}"
		update_script_path="none"
	else
		echo "${update_script_text}" | sudo tee "${updater_path}/${script_filename}" >/dev/null
		update_script_path="${script_filename}"
	fi

	record="${gh_name} \"${asset_path}\" ${asset_type} ${version} \"${update_script_path}\" \"${cache_filename}\" \"${timestamp}\""
	filename="${app_name}.${user_name}.rec"
	script_filename="${app_name}.${user_name}.sh"
	
	echo "#github_name	asset_path	asset_type(source,deb,binary,git)	version	update_script_name	filename_in_cache timestamp" | sudo tee ${updater_path}/${filename} >/dev/null
	echo "$record" | sudo tee -a ${updater_path}/${filename} >/dev/null
}

function read_update_hook {
	local gh_name="$1"

	local updater_path=/usr/local/lib/adam/updater/records

	if [[ "$gh_name" == "" ]]; then
		pattern="([^/]+)/([^/]+)"
		if [[ "$gh_name" =~ $pattern ]]; then
			app_name=${BASH_REMATCH[2]}
			user_name=${BASH_REMATCH[1]}
		else
			errcho "Cannot parse github name. Must be in format <user>/<repo>"
			return 1
		fi
	fi
	filename="${app_name}.${user_name}.rec"
	if [ -f "${updater_path}/${filename}" ]; then
		eval "recs=( $(tail -n 1 "${updater_path}/${filename}") )"
		gh_name="${recs[0]}"
		asset_path="${recs[1]}"
		asset_type="${recs[2]}"
		version="${recs[3]}"
		update_script_path="${recs[4]}"
		cache_filename="${recs[5]}"
		timestamp="${recs[6]}"
		if [ "$(dirname "$update_script_path")" == "" ]; then
			 update_script_path="${updater_path}/${update_script_path}"
		fi
	fi
}

function install_gh_source {
	#Installs source tarball from the github in the dest_dir, setting
	#update hooks
	local gh_name="$1"
	local dest_dir="$2"
	local update_script_text="$3"
	local override_name="$4"
	local override_user="$5"
	
	local link="$(get_github_source_zipball "$gh_name")"
	local version="$(get_latest_github_release_name "$gh_name")"

	if [[ "$gh_name" == "" ]]; then
		pattern="([^/]+)/([^/]+)"
		if [[ "$gh_name" =~ $pattern ]]; then
			app_name=${BASH_REMATCH[2]}
			user_name=${BASH_REMATCH[1]}
		else
			errcho "Cannot parse github name. Must be in format <user>/<repo>"
			return 1
		fi
	fi
	
	if [[ "$override_name" != "" ]]; then
		app_name="$override_name"
	fi

	if [[ "$override_user" != "" ]]; then
		usergr="$override_user"
	else
		usergr=$(get_usergr_owner_of_file "${dest_dir}")
	fi
	
	filename="updater/${app_name}-${version}.zip"
	
	
	filepath="$(get_cached_file "$filename" "$link")"
	uncompress_cached_file "$filepath" "$dest_dir" "$usergr" "$app_name" skip_timestamps

	install_update_hook "$gh_name" "${dest_dir}/${app_name}" source "$version" local "$update_script_text" "$filename"
}



function install_gh_binary {
	#Installs tarball with binary from the github in the dest_dir, setting
	#update hooks
	set -x
	local gh_name="$1"
	local dest_dir="$2"
	local binary_relpath="$3"
	local override_name="$4"
	local override_user="$5"
	local override_arch="$6"
	local bindir="$7"
	local override_exe_name="$8"
		
	local link="$(get_app_link_gh "$gh_name" "${override_arch}" "tar\.gz")"
	if [[ "$link" == "" ]]; then
		set +x
		return 1
	fi

	local version="$(get_latest_github_release_name "$gh_name")"

	if [[ "$gh_name" != "" ]]; then
		pattern="([^/]+)/([^/]+)"
		if [[ "$gh_name" =~ $pattern ]]; then
			app_name=${BASH_REMATCH[2]}
			user_name=${BASH_REMATCH[1]}
		else
			errcho "Cannot parse github name. Must be in format <user>/<repo>"
			return 1
		fi
	fi
	
	if [[ "$bindir" == "" ]]; then
		bindir=/usr/local/bin
	fi
	
	if [[ "$override_name" != "" ]]; then
		app_name="$override_name"
	fi

	if [[ "$override_user" != "" ]]; then
		usergr="$override_user"
	else
		usergr=$(get_usergr_owner_of_file "${dest_dir}")
	fi

	if [[ "$override_exe_name" == "" ]]; then
		override_exe_name="${app_name}"
	fi
	
	filename="updater/$(basename "$link")"	

	filepath="$(get_cached_file "$filename" "$link")"
	if [ ! -f "${dest_dir}/${app_name}/${binary_relpath}" ]; then
		uncompress_cached_file "$filepath" "$dest_dir" "$usergr" "$app_name" skip_timestamps
	fi
	#make_symlink /usr/local/share/bandwhich/bandwhich /usr/local/bin/bandwhich

	make_symlink "${dest_dir}/${app_name}/${binary_relpath}" "${bindir}/${override_exe_name}"
	install_update_hook "$gh_name" "${dest_dir}/${app_name}" source "$version"  "$update_script_text" "$filename"
	chmod_file ${dest_dir}/${app_name}/${binary_relpath} 
	set +x
}

function install_gh_deb {
	#Installs deb from the github
	set -x
	local gh_name="$1"
	local override_arch="$2"
		
	local link="$(get_app_link_gh "$gh_name" "${override_arch}" deb)"
	if [[ "$link" == "" ]]; then
		set +x
		return 1
	fi
	local version="$(get_latest_github_release_name "$gh_name")"

	if [[ "$gh_name" != "" ]]; then
		pattern="([^/]+)/([^/]+)"
		if [[ "$gh_name" =~ $pattern ]]; then
			app_name=${BASH_REMATCH[2]}
			user_name=${BASH_REMATCH[1]}
		else
			errcho "Cannot parse github name. Must be in format <user>/<repo>"
			return 1
		fi
	fi
	
	filename="updater/$(basename "$link")"	

	filepath="$(get_cached_file "$filename" "$link")"
	
	install_apt_package_file "${filepath}" ripgrep

	install_update_hook "$gh_name" "${dest_dir}/${app_name}" deb "$version"  "" "$filename"
	set +x
}

function get_github_source_zipball {
	# Attention! You need to rename the file returned by the link
	local name="$1" # e.g. "BurntSushi/ripgrep"
	curl -s https://api.github.com/repos/$1/releases/latest | jq -r ".zipball_url"
}

function is_arch_supported {
	local releases="$1"
	local regexp="$2"
	ans="$(echo "$1" | grep -E "[_\-]$2")"
	
	echo "$ans"
	if [[ "$ans" == "" ]]; then
		return 0
	else
		return 1
	fi
}


function install_app_tar_gz {
	local name="$1"
	local download_link="$2"
	local filename="$3"
	local exe_name="$4"
	local user="$5"
	if [[ "$exe_name" == "" ]]; then
		exe_name="$name"
	fi
	if [[ "$user" == "" ]]; then
		user=$USER
	fi
	local dest_folder=/usr/local/share
	filepath=$(get_cached_file "$filename" "$download_link")
	get_from_cache_and_uncompress_file "$filepath" "${dest_folder}" "$user" "${name}" 
	if [ ! -d "${dest_folder}/${name}" ]; then
		pattern='(.*)\.tar.*$'
		if [[ "$filename" =~ $pattern ]]; then
			dirname="${BASH_REMATCH[1]}"
			if [ -d "${dest_folder}/${dirname}" ]; then
				sudo mv "${dest_folder}/${dirname}" "${dest_folder}/${name}"
			fi
		fi 
	fi

	if [ -f "${dest_folder}/${name}/${exe_name}" ]; then
		make_symlink "${dest_folder}/${name}/${exe_name}" "/usr/local/bin/${exe_name}"
	else
		errcho "Cannot find the application!"
	fi
}

function github_install_app {
	local gh_name="$1"
	local app_name="$2"
	local exe_name="$3"
	local force="$4"
	local user="$5"
	
	if [[ "$user" == "" ]]; then
		user=root
	fi

	if [[ "$app_name" == "" ]]; then
		pattern="([^/]+)/([^/]+)"
		if [[ "$gh_name" =~ $pattern ]]; then
			app_name=${BASH_REMATCH[2]}
		else
			errcho "Cannot parse github name. Must be in format <user>/<repo>"
			return 1
		fi
	fi
	
	if [[ "$exe_name" == "" ]]; then
		exe_name="$app_name"
	fi
	
	if [[ "$force" == "" ]]; then
		if which "$exe_name" >/dev/null; then
			return 0 #Already installed
		fi
	fi 

	
	download_link=$(get_app_link_gh "${gh_name}")
	local filename
	pattern='.*/([^/]+)$'
	if [[ "$download_link" =~ $pattern ]]; then
		filename="${BASH_REMATCH[1]}"
	else
		errcho "Cannot parse download link from github: $download_link"
		return 1
	fi
	pattern1='\.tar\.gz$'
	pattern2='\.deb$'
	
	if [[ "$download_link" =~ $pattern1 ]]; then
		install_app_tar_gz "$app_name" "$download_link" "$filename" "$exe_name" "$user"
	else
		install_apt_package_file "$filename" "$app_name" "$download_link"
	fi
}

function github_update_app {
	set -x
	local gh_name="$1"
	local app_name="$2"
	local exe_name="$3"
	local force="$4"

	if [[ "$app_name" == "" ]]; then
		pattern="([^/]+)/([^/]+)"
		if [[ "$gh_name" =~ $pattern ]]; then
			app_name=${BASH_REMATCH[2]}
		else
			errcho "Cannot parse github name. Must be in format <user>/<repo>"
			return 1
		fi
	fi
	
	if [[ "$exe_name" == "" ]]; then
		exe_name="$app_name"
	fi
	
	if [[ "$force" == "" ]]; then
		if ! which "$exe_name" >/dev/null; then
			set +x
			return 0 #Not installed
		fi
	fi 

	gh_version=$(get_latest_github_release_name "$gh_name" skip_v)
	local_version=$(get_app_version "$exe_name")
	
	if [[ "$gh_version" != "$local_version" ]]; then
		github_install_app "$gh_name" "$app_name" "$exe_name" force
	fi
}
