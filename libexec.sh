#!/bin/bash 

# reads dependencies from the given file into an array "dependencies"
function read_file_header {
	local input_file="$1"
	local pattern1='^ *## *dependency: *(.*)$'
	local pattern2='^[^ ^#].*$'
	local line
	if [ -f "${input_file}" ]; then
		while read -r line; do
			if [[ "$line" =~ $pattern1 ]]; then
				add_dependency "${BASH_REMATCH[1]}"
			elif [[ "$line" =~ $pattern2 ]]; then
				break
			fi
		done < "$input_file"
	else
		errcho "Cannot find file $input_file"
		exit 1
	fi
}

function add_dependency {
	local new_entry="$1"
	local ee
	for ee in "${dependencies[@]}"; do
		if [[ "$ee" == "$new_entry" ]]; then
			return
		fi
	done
	dependencies+=("$new_entry")
}

function collect_dependencies {
	local input_file="$1"
	dependencies=()
	read_file_header $input_file
	local dep_len=${#dependencies[@]}
	local old_dep_len=0
	
	while true; do
		
		if [[ "${dep_len}" != "${old_dep_len}" ]]; then
			for ee in "${dependencies[@]}"; do
				read_file_header $ee
			done
			old_dep_len=$dep_len
			dep_len=${#dependencies[@]}
		else
			break
		fi
	done
}


