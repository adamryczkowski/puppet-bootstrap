#!/bin/bash



function calcshasum() {
	file="$1"
	local shasum
	if [ -f "$file" ]; then
		shasum=$(shasum "$file")
		local pattern='^([^ ]+) '
		if [[ "$shasum" =~ $pattern ]]; then
			shasum=${BASH_REMATCH[1]}
		else
			errcho "Wrong shasum format"
		fi
	else
		shasum=""
	fi
	echo "$shasum"
}

function apply_patch() {
	local file="$1"
	local hash_orig="$2"
	local hash_dest="$3"
	local patchfile="$4"
	local shasum
	if [ -f "$file" ] && [ -f "$patchfile" ]; then
		shasum=$(calcshasum "$file")
		if [[ "$shasum" == "$hash_orig" ]]; then
			if patch --dry-run "$file" "$patchfile" >/dev/null; then
				if [ -w "$file" ]; then
					logexec patch "$file" "$patchfile"
				else
					logexec sudo patch "$file" "$patchfile"
				fi
			else
				errcho "Error while applying the patch"
			fi
		elif [[ "$shasum" == "$hash_dest" ]]; then
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

function edit_bash_augeas() {
	local file=$1
	local var=$2
	local value=$3
	local oldvalue
	install_apt_package augeas-tools augtool
	oldvalue=$(sudo augtool -L -A --transform "Shellvars incl $file" get "/files${file}/${var}" | sed -En 's/\/.* = \"?([^\"]*)\"?$/\1/p')
	if [ "$value" != "$oldvalue" ]; then
		logexec sudo augtool -L -A --transform "Shellvars incl $file" set "/files${file}/${var}" "${value}" >/dev/null
	fi
}

function logmkdir() {
	local dir=$1
	local user
	if [ -z ${2+x} ]; then
		user=""
	else
		user="$2"
	fi
	if ! [ -d "$dir" ]; then
		if ! mkdir -p "$dir"; then
			logexec sudo mkdir -p "$dir"
		fi
	fi
	if [ -n "$user" ]; then
		curuser=$(stat -c '%U' "${dir}")
		if [[ "$curuser" != "$user" ]]; then
			# Check the owner of the directory
			logexec sudo chown -R "${user}:${user}" "$dir"
		fi
	fi
}

function linetextfile() {
	local plik="$1"
	local line="$2"
	if ! grep -qF -- "$line" "$plik"; then
		if [ -w "$plik" ]; then
			#			$loglog
			echo "$line" >> "$plik"
		else
			#			$loglog
			echo "$line" | sudo tee -a "$plik"
		fi
		return 0
	fi
	return 0
}

function multilinetextfile() {
	# Makes sure the paragraph passed indirectly as a Bash variable name,
	# is present in the file.
	local plik="$1"
	local variablename="$2"

	local contents="${variablename}"

	if [ -z "$contents" ]; then
		errcho "Empty contents to multilinetextfile"
		return 1
	fi
	if [ -z "$plik" ]; then
		errcho "Empty file name to multilinetextfile"
		return 1
	fi

	local joined=${contents//$'\n'/\\n}
	joined=${joined//\$/\\\$}
	joined=${joined//\[/\\\[}
	joined=${joined//\]/\\\]}
	joined=${joined//\)/\\\)}
	joined=${joined//\(/\\\(}
	joined=${joined//\*/\\\*}
	joined=${joined//\?/\\\?}

	if grep -Poz -- "$joined" "$plik" >/dev/null; then
		return 0
	fi
	if [ -w "$plik" ]; then
		echo "$contents" >> "$plik"
	else
		echo "$contents" | sudo tee -a "$plik" >/dev/null
	fi
	return 0
}


function textfile() {
	local plik=$1
	local contents=$2
	local user=$3

	if [ -z "$user" ]; then
		user="$USER"
	fi

	local flag=0
	logmkdir "$(dirname "${plik}")" "$user"
	if [ ! -f "${plik}" ]; then
		flag=1
	else
		tmpfile=$(mktemp)
		echo "$contents" > "${tmpfile}"
		if ! cmp "$tmpfile" "$plik"; then
			flag=1
		fi
	fi
	if [ "$flag" == "1" ]; then
		if [ -w "${plik}" ] && [ "$user" == "$USER" ]; then
			loglog
			echo "$contents" | tee "${plik}" >/dev/null
		else
			loglog
			echo "$contents" | sudo -u "$user" -- tee "${plik}" >/dev/null
		fi
		return 0
	fi
	return 0
}


function install_file() {
	local input_file="$1"
	local dest="$2"
	local user=$3
	local set_executable

	if [ -z ${4+x} ]; then
		set_executable=0
	else
		set_executable="$4"
	fi

	if [ -z "${user}" ]; then
		user=auto
	fi
	if [ ! -f "${input_file}" ]; then
		errcho "Cannot find ${input_file}"
		#		return 1
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
		if [ -w "$(dirname $dest)" ]; then
			logexec cp "$input_file" "$dest"
		else
			logexec sudo cp "$input_file" "$dest"
		fi
	fi
	if [ ! -f "$dest" ]; then
		errcho "Error when copying ${input_file} into ${dest}"
		#		return 1
	fi
	if [ "$user" != "auto" ]; then
		cur_owner="$(stat --format '%U' "$dest")"
		if [ "$user" != "$cur_owner" ]; then
			if [ -w "$dest" ]; then
				logexec chown "$user" "$dest"
			else
				logexec sudo chown "$user" "$dest"
			fi
		fi
	fi
	if [ -n "$set_executable" ]; then
		if [ "$user" != "$cur_owner" ]; then
			if [ -w "$dest" ]; then
				logexec chmod +x "$dest"
			else
				logexec sudo chmod +x "$dest"
			fi
		fi
	fi
}

function set_executable() {
	local input_file="$1"

	if [ -f "$input_file" ]; then
		if [[ ! -x "$input_file" ]]; then
			if [ -w "$input_file" ]; then
				logexec chmod +x "$input_file"
			else
				logexec sudo chmod +x "$input_file"
			fi
		fi
		if [[ ! -x "$input_file" ]]; then
			errcho "Cannot set executable permission to $input_file"
			return 1
		fi
	else
		errcho "File $input_file is not found"
		return 1
	fi
}

function set_non_executable() {
	local dest="$1"
	if [ -f "$dest" ]; then
		if [[ -x "$dest" ]]; then
			if [ -w "$dest" ]; then
				logexec chmod -x "$dest"
			else
				logexec sudo chmod -x "$dest"
			fi
		fi
		if [[ -x "$dest" ]]; then
			errcho "Cannot unset executable permission to $dest"
			return 1
		fi
	else
		errcho "File $dest is not found"
		return 1
	fi
}

function install_script() {
	local input_file="$1"
	local dest_folder="$2"
	local set_executable="$3"
	local user
	if [ -z ${4+x} ]; then
		user="$USER"
	else
		user="${4}"
	fi
	logmkdir "$dest_folder" "$user"
	install_file "$input_file" "$dest_folder" "$user" "$set_executable"
}

function install_data_file() {
	local input_file="$1"
	local dest="$2"
	local user=$3
	install_file "$input_file" "$dest" "$user"
	set_non_executable "$dest"
}

function chmod_file() {
	local file="$1"
	local desired_mode="$2"
	local pattern='^[[:digit:]]+$'
	local actual_mode
	if [[ ! "${desired_mode}" =~ $pattern ]]; then
		errcho "Wrong file permissions. Needs octal format."
		return 1
	fi
	if [ ! -f "${file}" ]; then
		errcho "File ${file} doesn't exist"
		return 1
	fi
	actual_mode=$(stat -c "%a" "${file}")
	if [ "${desired_mode}" != "${actual_mode}" ]; then
		logexec sudo chmod "${desired_mode}" "${file}"
	fi
}

function chmod_dir() {
	local file=$1
	local desired_mode_dir=$2
	local desired_mode_file=$3
	local desired_mode_exec_file=$4
	local pattern='^[[:digit:]]+$'
	local actual_mode
	if [[ ! "${desired_mode_file}" =~ $pattern ]]; then
		errcho "Wrong file permissions. Needs octal format."
		return 1
	fi
	if [[ ! "${desired_mode_dir}" =~ $pattern ]]; then
		errcho "Wrong dir permissions. Needs octal format."
		return 1
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

function chown_dir() {
	local file=$1
	local user=$2
	local group=$3

	if [ -z "$group" ]; then
		group="$user"
	fi

	if [ -z "$user" ]; then
		errcho "No user name exitting"
		return 1
	fi
	if [ -z "$file" ]; then
		errcho "No path. Exiting"
		return 1
	fi
	if [ ! -d "${file}" ]; then
		errcho "File ${file} doesn't exist"
		return 1
	fi
	logexec sudo find "$file" -not -user "$user" -or -not -group "$group" -exec chown "${user}:${group}" {} \;
}

function download_file() {
	# Downloads the file from the link, if the file does not exist
	local filename="$1"
	local download_link="$2"

	if [ -z "$filename" ]; then
		errcho "No filename provided"
		return 1
	fi
	if [ -z "$download_link" ]; then
		errcho "No download link provided"
		return 1
	fi
	if [ ! -f "$filename" ]; then
		if [ -w "$(dirname "$filename")" ]; then
			logexec wget -c "$download_link" -O "$filename"
		else
			logexec sudo wget -c "$download_link" -O "$filename"
		fi
	fi
	if [ ! -f "$filename" ]; then
		errcho "Cannot download the file"
		return 1
	fi
}


# returns path
function get_cached_file() {
	local filename="$1"
	local download_link="$2"
	if [ ! -d "${repo_path}" ]; then
		mkdir -p "/tmp/repo_path/$(dirname "${filename}")"
		local repo_path="/tmp/repo_path"
	fi
	if [ ! -f "${repo_path}/${filename}" ]; then
		if [ -z "$download_link" ]; then
			errcho "File is missing from cache"
			return 1
		fi
		if [ ! -w "${repo_path}" ]; then
			if ! sudo chown "${USER}" "${repo_path}"; then
				echo "Cannot write to the repo ${repo_path}" >/dev/stderr
				return 1
			fi
			local repo_path="/tmp/repo_path"
			mkdir -p /tmp/repo_path
		fi
		wget -c "${download_link}" -O "${repo_path}/${filename}"
	fi
	if [ ! -f "${repo_path}/${filename}" ]; then
		errcho "Cannot download the file"
		return 1
	fi
	echo "${repo_path}/${filename}"
}

#function logexec {
#	exec "$@" | true
#}

function extract_archive_flat() {
	#'extracts all files in the archive to the destination_parent, ignoring any paths within the archive.
	local archive_path="$1"
	local destination_folder="$2"
	local act_as_user="$3"
	if [[ "$archive_path" != /* ]]; then
    archive_path="$(pwd)/$archive_path"
  fi
  if [[ "$destination_folder" != /* ]]; then
    destination_folder="$(pwd)/$destination_folder"
  fi
  make_sure_dtrx_exists
	logmkdir "${destination_folder}" "$act_as_user"
	pushd "${destination_folder}" || return 1
	dtrx --one=here "$archive_path"
	popd
}

function extract_archive() {
	local archive_path="$1"
	local destination_parent="$2"
	local act_as_user="$3"
	local single_item_policy="$4" #'rename' - if archive with single folder - the files in that  folder will be extracted to the extracted_name subfolder of the destination_parent. The same, if archive with a single file - that file will be renamed into extracted_name, and put in destination_parent.
	#'original' - (default) the archive with single folder will be extracted directly to destination_parent, ignoring extracted_name. Similarily, if archive with a single file - that file will be extracted in the destination_parent under its original name.
	#'onedir' - if archive with single folder - acts exactly as 'rename' policy. If archive with a single file - that file will be put in the subfolder extracted_name with the name extracted_name.
	local extracted_name="$5" #Defaults to the archive name minus extensions

  # Make sure archive_path is absolute
  if [[ "$archive_path" != /* ]]; then
    archive_path="$(pwd)/$archive_path"
  fi

	if [[ "$single_item_policy" == "" ]]; then
		single_item_policy=original
	fi

	if [[ "$extracted_name" == "" ]]; then
		#		local extension="${archive_path##*.}"
		extracted_name="${archive_path%.*}"
	fi
	make_sure_dtrx_exists

	local dest_path="${destination_parent}/${extracted_name}"
	logmkdir "${dest_path}" "$act_as_user"
	if is_folder_writable "$(dirname "$destination_parent")" "$act_as_user"; then
		if [ "$act_as_user" == "$USER" ]; then
			mode=1
			pushd "${dest_path}"
			dtrx --one here "$archive_path"
			popd
		else
			mode=2
			pushd "${dest_path}" || return 1
			sudo -u "$act_as_user" "$(which dtrx)" --one here "$archive_path"
			popd
		fi
	else
		mode=2
		pushd "${dest_path}" || return 1
		sudo -u "$act_as_user" "$(which dtrx)" --one here "$archive_path"
		popd
	fi

	filecount="$(find "${dest_path}" -mindepth 1 -maxdepth 1 | wc -l)"
	if [[ $filecount == 1 ]]; then
		filename1=$(find "${dest_path}" -mindepth 1 -maxdepth 1 | head -n 1)
		filename1=$(get_relative_path "${dest_path}" "${filename1}")
		if [ -d "${dest_path}/${filename1}" ]; then


			if [[ $single_item_policy == original ]]; then
				if [[ $mode == 1 ]]; then
					mv "${dest_path}/${filename1}" "${destination_parent}/${filename1}"
					rmdir "${dest_path}"
				else
					sudo -u "$act_as_user" mv "${dest_path}/${filename1}" "${destination_parent}/${filename1}"
					sudo -u "$act_as_user" rmdir "${dest_path}"
				fi


			elif [[ $single_item_policy == rename || $single_item_policy == onedir ]]; then
				if [[ $mode == 1 ]]; then
					find "${dest_path}/${filename1}/" -mindepth 1 -maxdepth 1 -exec mv -t "${dest_path}" -- {} +
					rmdir "${dest_path}/${filename1}"
				else
					sudo -u "$act_as_user" find "${dest_path}/${filename1}/" -mindepth 1 -maxdepth 1 -exec mv -t "${dest_path}" -- {} +
					sudo -u "$act_as_user" rmdir "${dest_path}/${filename1}"
				fi
			fi
		elif [ -f "${dest_path}/${filename1}" ]; then


			if [[ $single_item_policy == original ]]; then
				if [[ $mode == 1 ]]; then
					mv "${dest_path}/${filename1}" "${destination_parent}/${filename1}"
					rmdir "${dest_path}"
				else
					sudo -u "$act_as_user" mv "${dest_path}/${filename1}" "${destination_parent}/${filename1}"
					sudo -u "$act_as_user" rmdir "${dest_path}"
				fi


			elif [[ $single_item_policy == rename ]]; then
				if [[ $mode == 1 ]]; then
					tmpname=$(mktemp -p "${destination_parent}" --dry-run)
					mv "${dest_path}/${filename1}" "${tmpname}"
					rmdir "${dest_path}"
					mv "${tmpname}" "${dest_path}"
				else
					tmpname=$(sudo -u "$act_as_user" mktemp -p "${destination_parent}" --dry-run)
					sudo -u "$act_as_user" mv "${dest_path}/${filename1}" "${tmpname}"
					sudo -u "$act_as_user" rmdir "${dest_path}"
					sudo -u "$act_as_user" mv "${tmpname}" "${dest_path}"
				fi


			elif [[ $single_item_policy == onedir ]]; then
				if [[ $mode == 1 ]]; then
					mv "${dest_path}/${filename1}" "${dest_path}/${extracted_name}"
				else
					sudo -u "$act_as_user" mv "${dest_path}/${filename1}" "${dest_path}/${extracted_name}"
				fi
			fi
		fi
	fi
}


# shellcheck disable=SC2120
function make_sure_dtrx_exists() {
	# TODO: Re-implement this function using libpipx.sh.
	local mute="$1"
	if ! which dtrx >/dev/null; then
		if [[ $mute == "" ]]; then
			install_apt_package dtrx dtrx
		else
			install_apt_package dtrx dtrx >/dev/null 2>/dev/null
		fi
		# shellcheck disable=SC2181
		if [[ "$?" != "0" ]]; then
			install_apt_package pipx pipx
			if [[ $mute == "" ]]; then
				install_pipx_command dtrx
			else
				install_pipx_command dtrx >/dev/null 2>/dev/null
			fi
			add_path_to_bashrc "$(get_home_dir)/.local/bin"
			#			make_sure_dir_is_in_a_path "$(get_home_dir)/.local/bin"
		fi
	fi
	which dtrx >/dev/null
}


#function get_from_cache_and_uncompress_file {
#	local filename="$1"
#	local download_link="$2"
#	local destination_parent="$3"
#	local folder_name="$4"
#	local usergr="$5"
#	local user
#	if [ -z "$usergr" ]; then
#		user=$USER
#		usergr=$user
#		group=""
#	else
#		local pattern='^([^:]+):([^:]+)$'
#		if [[ "$usergr" =~ $pattern ]]; then
#			group=${BASH_REMATCH[2]}
#			user=${BASH_REMATCH[1]}
#		else
#			group=""
#			user=$usergr
#		fi
#	fi
#
#	if [ ! -f "$filename" ]; then
#		path_filename=$(get_cached_file "$filename" "${download_link}")
#	else
#		path_filename="$filename"
#	fi
#	if [ -z "$path_filename" ]; then
#		echo "no input file $path_filename"
#		return 1
#	fi
#	if [ -z "$destination_parent" ]; then
#		echo "no destination $destination_parent"
#		return 2
#	fi
#	if [ -d "$destination_parent" ]; then
#		moddate_remote=$(stat -c %y "$destination_parent")
#		if [ -f "$timestamp_path" ]; then
#			moddate_hdd=$(cat "$timestamp_path")
#			if [ "$moddate_hdd" == "$moddate_remote" ]; then
#				return 0
#			fi
#		fi
#	fi
#
#	extract_archive "$path_filename" "$destination_parent" "$folder_name" "$user"
#	local timestamp_path="${destination_parent}/${folder_name}.timestamp"

#	if [[ $mode == 1 ]]; then
#		echo "$moddate_remote" | tee "$timestamp_path" >/dev/null
#	elif [[ $mode == 2 ]]; then
#		echo "$moddate_remote" | sudo -u "$user" -- tee "$timestamp_path" >/dev/null
#	fi
#}

function uncompress_cached_file() {
	local filename="$1"
	local destination_parent="$2"
	local group
	local user
	local usergr
	local timestamp_path
	if [ -n "$3" ]; then
		usergr="$3"
	fi

	if [ -n "$4" ]; then
		local extracted_name="$4"
	fi
	if [ "$5" != "" ]; then
		local skip_timestamps="$5"
	fi
	local user
	if [ -z "$usergr" ]; then
		user=$USER
		usergr=$user
		group="$(id -gn)"
	else
		local pattern='^([^:]+):([^:]+)$'
		if [[ "$usergr" =~ $pattern ]]; then
			group=${BASH_REMATCH[2]}
			user=${BASH_REMATCH[1]}
		else
			group=""
			user=$usergr
		fi
	fi
	if [ -z "$extracted_name" ]; then
		basename_extension "$filename"
		extracted_name=$(basename "$base")
		#		errcho "Empty extracted_name argument to uncompress_cached_file"
	fi

	if [ ! -f "$filename" ]; then
		path_filename=$(get_cached_file "$filename")
	else
		path_filename="$filename"
	fi
	if [ -z "$path_filename" ]; then
		echo "no input file $path_filename"
		return 1
	fi
	if [ -z "$destination_parent" ]; then
		echo "no destination $destination_parent"
		return 2
	fi
	if [[ "$skip_timestamps" == "" ]]; then
		if [ -d "$destination_parent" ]; then
			moddate_remote=$(stat -c %y "$destination_parent")
			timestamp_path="$(dirname "${destination_parent}")/${extracted_name}/.timestamp"
			if [ -f "$timestamp_path" ]; then
				moddate_hdd=$(cat "$timestamp_path")
				if [ "$moddate_hdd" == "$moddate_remote" ]; then
					return 0
				fi
			fi
		fi
	fi
	extract_archive "$path_filename" "$destination_parent" "$user" onedir "$extracted_name"


	if [[ "$skip_timestamps" == "" ]]; then
		if [[ $mode == 1 ]]; then
			echo "$moddate_remote" | tee "$timestamp_path" >/dev/null
		elif [[ $mode == 2 ]]; then
			echo "$moddate_remote" | sudo -u "$user" -- tee "$timestamp_path" >/dev/null
		fi
	fi
}

function cp_file() {
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
		destfile="$(basename "$source")"
	else
		destdir="$(dirname "$dest")"
		destfile="$(basename "$dest")"
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

function is_folder_writable() {
	local folder="$1"
	local user="$2"


	#source: https://stackoverflow.com/questions/14103806/bash-test-if-a-directory-is-writable-by-a-given-uid
	# Use -L to get information about the target of a symlink,
	# not the link itself, as pointed out in the comments
#	mapfile -t INFO < <(stat -L -c "0%a %G %U" "$folder")
	read -a INFO <<< "$(stat -L -c "0%a %G %U" "$folder")"
	PERM=${INFO[0]}
	GROUP=${INFO[1]}
	OWNER=${INFO[2]}

	ACCESS=no
	if (( (PERM & 0002) != 0 )); then
		# Everyone has write access
		ACCESS=yes
	elif (( (PERM & 0020) != 0 )); then
		# Some group has write access.
		# Is user in that group?
#		mapfile -t gs < <(groups "$user")
		read -a gs <<< "$(groups "$user")"
		for g in "${gs[@]}"; do
			if [[ $GROUP == "$g" ]]; then
				ACCESS=yes
				break
			fi
		done
	elif (( (PERM & 0200) != 0 )); then
		# The owner has write access.
		# Does the user own the file?
		[[ $user == "$OWNER" ]] && ACCESS=yes
	fi
	if [ "$ACCESS" == 'yes' ]; then
		return 0
	else
		return 1
	fi
}

function get_usergr_owner_of_file() {
	local path="$1"
	stat -c '%U:%G' "${path}"
}

function get_files_matching_regex() {
	local path="$1"
	local regex="$2"
	local recurse="$3"

	if [ -z "$recurse" ]; then
		grep -HiRE "$regex" "$path" #H for file printing, i for case-insensitive, R for recursive search, E for regex
	else
		grep -HiE "$regex" "$path" #H for file printing, i for case-insensitive, R for recursive search, E for regex
	fi
}

function get_relative_path() {
	local base_path="$1"
	local target_path="$2"
	install_apt_package python3
	python3 -c "import os.path; print(os.path.relpath('$target_path', '$base_path'))"
}

function guess_repo_path() {
	local guess="$1"
	if [ -f "${guess}/repo_path" ]; then
		export repo_path="$guess"
	fi
}

function basename_extension() {
	#from https://stackoverflow.com/a/1403489/1261153
	local filename="$1"
	base="${filename%.[^.]*}"                       # Strip shortest match of . plus at least one non-dot char from end
	ext="${filename:${#base} + 1}"                  # Substring from len of base thru end
	if [[ -z "$base" && -n "$ext" ]]; then          # If we have an extension and no base, it's really the base
		base=".$ext"
		ext=""
		return
	fi
	local base2="${base%.[^.]*}"
	local ext2="${base:${#base2} + 1}"
	if [[ "$ext2" == "tar" ]]; then
		ext="tar.${ext}"
		base="$base2"
	fi
}

function make_symlink() {
	local source="$1"
	local dest="$2"
	if [ ! -f "$source" ] && [ ! -d "$source" ]; then
		errcho "$source does not exist"
		return 1
	fi
	if [ -L "$dest" ]; then
		if [ "$(readlink -f "$dest")" != "$(readlink -f "$source")" ]; then
			if is_folder_writable "$(dirname "$dest")" "$user"; then
				$logexec rm "$dest"
				$logexec ln -s "$source" "$dest"
			else
				$logexec sudo rm "$dest"
				$logexec sudo ln -s "$source" "$dest"
			fi
		fi
		return 0
	else
		if [ -f "$dest" ] || [ -d "$dest" ]; then
			errcho "$dest already exists"
			return 1
		fi
		if is_folder_writable "$(dirname "$dest")" "$user"; then
			logexec ln -s "$source" "$dest"
		else
			logexec sudo ln -s "$source" "$dest"
		fi
		return 0
	fi
}
