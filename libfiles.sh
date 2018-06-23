#!/bin/bash
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

function chmod_dir {
	local file=$1
	local desired_mode_dir=$2
	local desired_mode_file=$3
	local desired_mode_exec_file=$4
	local pattern='^\d+$'
	local actual_mode
	if [[ ! "${desired_mode_file}" =~ $pattern ]]; then
		errcho "Wrong file permissions. Needs octal format."
		exit 1
	fi
	if [[ ! "${desired_mode_dir}" =~ $pattern ]]; then
		errcho "Wrong dir permissions. Needs octal format."
		exit 1
	fi
	if [ ! -d "${file}" ]; then
		errcho "File ${file} doesn't exist"
		return 1
	fi
	logexec sudo find "$file" -type d -not -perm "$desired_mode_dir" -exec chmod "$desired_mode_dir" {} \;
	if [ -z "$desired_mode_file" ]; then
		logexec sudo find "$file" -type f -not -perm "$desired_mode_file" -exec chmod "$desired_mode_file" {} \;
	else
		logexec sudo find "$file" -type f -perm /111 -not -perm "$desired_mode_exec_file" -exec chmod "$desired_mode_exec_file" {} \;
		logexec sudo find "$file" -type f -not -perm /111 -not -perm "$desired_mode_file" -exec chmod "$desired_mode_file" {} \;
	fi
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
		if [ -z "$download_link" ]; then
			errcho "File is missing from cache"
			return 1
		fi
		wget -c "${download_link}" -O "${repo_path}/${filename}"
	fi
	if [ ! -f "${repo_path}/${filename}" ]; then
		errcho "Cannot download the file"
		return 1
	fi
	echo "${repo_path}/${filename}"
}

function uncompress_cached_file {
	local filename="$1"
	local destination="$2"
	local user="$3"
	
	if [ -z "$user" ]; then
		user=$USER
	fi
	
	path_filename=$(get_cached_file "$filename")
	if [ -z "$path_filename" ]; then
		return 1
	fi
	if [ -z "$destination" ]; then
		return 2
	fi
	if is_folder_writable "$destination" "$user"; then
		if [ "$user" == "$USER" ]; then
			logexec tar -xvf "$path_filename" -C "$destination"
		else
			logexec sudo -u "$user" -- tar -xvf "$path_filename" -C "$destination"
		fi
	else
		sudo logexec sudo tar -xvf "$path_filename" -C "$destination"
		sudo logexec chown -R "$user" "$destination"
	fi
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

function is_folder_writable {
	local folder="$1"
	local user="$2"
	
	#source: https://stackoverflow.com/questions/14103806/bash-test-if-a-directory-is-writable-by-a-given-uid
	# Use -L to get information about the target of a symlink,
	# not the link itself, as pointed out in the comments
	INFO=( $(stat -L -c "0%a %G %U" $folder) )
	PERM=${INFO[0]}
	GROUP=${INFO[1]}
	OWNER=${INFO[2]}

	ACCESS=no
	if (( ($PERM & 0002) != 0 )); then
		# Everyone has write access
		ACCESS=yes
	elif (( ($PERM & 0020) != 0 )); then
		# Some group has write access.
		# Is user in that group?
		gs=( $(groups $user) )
		for g in "${gs[@]}"; do
			if [[ $GROUP == $g ]]; then
				ACCESS=yes
				break
			fi
		done
	elif (( ($PERM & 0200) != 0 )); then
		# The owner has write access.
		# Does the user own the file?
		[[ $user == $OWNER ]] && ACCESS=yes
	fi
	if [ "$ACCESS" == 'yes' ]; then
		return 0
	else
		return 1
	fi
}
