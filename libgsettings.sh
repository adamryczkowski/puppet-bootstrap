#!/bin/bash 

function gsettings_set_value {
	local schema=$1
	local name=$2
	local value=$3
	get_ui_context
	existing_value=$(gsettings get ${schema} ${name})
	if [ "$existing_value" != "$value" ]; then
		logexec gsettings set ${schema} ${name} ${value}
	fi
}

function set_mime_default {
	local filetype=$1
	local value=$2
	get_ui_context
	existing_value=$(xdg-mime query default ${filetype})
	if [ "$existing_value" != "$value" ]; then
		logexec xdg-mime default ${value} ${filetype}
	fi
}

function load_gsettings_array {
	local schema=$1
	local name=$2
	get_ui_context
	local existing_values=$(gsettings get ${schema} ${name})
	if [ -n "${existing_values}" ]; then
		local new_array=()
		local flag=0
		local oldifs=${IFS}
		export IFS="', '"
		for item in $existing_values; do
			if [[ "$item" != "" && "$item" != "[" && "$item" != "]" ]]; then
				new_array+=($item)
			fi
		done
		export IFS=${oldifs}
	fi
	(>&2 echo "Number of elements of new_array: ${#new_array[@]}")
	declare -p new_array | sed -e 's/^declare -a new_array=//'
}

function remove_item_from_array {
	get_ui_context
	eval "local -a input_array=$1"
	(>&2 echo "Number of elements of array: ${#input_array[@]}")
	local target=$2
	local -a output_array=()
	for value in "${input_array[@]}"; do
		if [[ $value != $target ]]; then
			output_array+=($value)
		fi
	done
	(>&2 echo "Number of elements of output_array: ${#output_array[@]}")
	declare -p output_array | sed -e 's/^declare -a output_array=//'
}

function find_item_in_array {
	get_ui_context
	eval "local -a array=$1"
	(>&2 echo "Number of elements of array: ${#array[@]}")
	local match="$2"
	local i=1
	for item in "${array[@]}"; do
		if [ "$item" == "$match" ]; then
			echo $i
			return 0
		fi
	done
	echo 0
	return 0
}

function add_item_to_array {
	get_ui_context
	eval "local -a array=$1"
	(>&2 echo "Number of elements of array: ${#array[@]}")
	local target=$2
	local position=$3
	
	index=$(find_item_in_array "$1" "$2")
	
	if [ "$index" != "0" ]; then
		if [ -n "${position}" ]; then
			if [ "$position" == "$index" ]; then
				return 0 #Element already present
			fi
		else
			if [ "$position" == "${#array[@]}" ]; then
				return 0 #Element already present
			fi
		fi
		eval "local -a array=$(remove_item_from_array "$1" "$2")"
		(>&2 echo "Number of elements of array: ${#array[@]}")
	fi
	if [ -n "${position}" ]; then
		local new_array=( "${array[@]:0:${position}}" "${target}" "${array[@]:${position}}" )
		declare -p new_array | sed -e 's/^declare -a new_array=//'
	else
		array+=($target)
		declare -p array | sed -e 's/^declare -a array=//'
		(>&2 echo "Number of elements of array: ${#array[@]}")
	fi
}

function set_gsettings_array {
	get_ui_context
	local schema=$1
	local name=$2
	local value_arr_str="$3"
	local i=1
	local old_value_str="$(load_gsettings_array ${schema} ${name})"
	if [ "$old_value_str" == "$value_arr_str" ]; then
		return 0 #nothing to do
	fi
	eval "local -a value_array=$3"
	(>&2 echo "Number of elements of value_array: ${#value_array[@]}")
	local ans="['"
	for value in "${value_array[@]}"; do
		if [ "$i" == "1" ]; then
			ans="${ans}${value}"
		else
			ans="${ans}', '${value}"
		fi 
		((i++))
	done
	ans="${ans}']"
	gsettings set ${schema} ${name} "${ans}"
}

function gsettings_add_to_array {
	local schema=$1
	local name=$2
	local value=$3
	local position=$4
	
	local existing_values_str=$(load_gsettings_array ${schema} ${name})
	
	local ans_str=$(add_item_to_array "${existing_values_str}" ${value} ${position})
	set_gsettings_array ${schema} ${name} "${ans_str}"
}

function gsettings_remove_from_array {
	local schema=$1
	local name=$2
	local value=$3
	
	local existing_values_str=$(load_gsettings_array ${schema} ${name})
	
	local ans_str=$(remove_item_from_array "${existing_values_str}" "${value}")
	set_gsettings_array ${schema} ${name} "${ans_str}"
}

function gsettings_remove_from_array2 {
	local schema=$1
	local name=$2
	local value=$3
	get_ui_context
	local existing_values=$(gsettings get ${schema} ${name})
	local change=0
	if [ -n "${existing_values}" ]; then
		local newvalue="['"
		local flag=0
		local oldifs=${IFS}
		export IFS="', '"
		for item in $existing_values; do
			if [[ "$item" != "" && "$item" != "[" && "$item" != "]" ]]; then
				if [ "${item}" != "${value}" ]; then
					if [ "${flag}" == "1" ]; then
						newvalue="${newvalue}', '${item}"
					else
						newvalue="${newvalue}${item}"
						flag=1
					fi
				else
					change=1
				fi
			fi
		done
		newvalue="${newvalue}']"
		export IFS=${oldifs}
	fi
	if [ "$change" == "1" ]; then
		echo "gsettings set ${schema} ${name} ${newvalue}"
		gsettings set ${schema} ${name} "${newvalue}"
	fi
}

function install_gnome_extension {
	local ext_path="$1"
	if [ -r "$ext_path" ]; then
		local ext_id=$(unzip -c "$ext_path" metadata.json | grep uuid | cut -d \" -f4)
		if [ -n "$ext_id" ]; then
			local ext_target_path="/usr/share/gnome-shell/extensions/${ext_id}"
			if [ ! -d "$ext_target_path" ]; then
				logexec unzip -q "$ext_path" -d "${ext_target_path}/"
			fi
			gsettings_add_to_array org.gnome.shell enabled_extensions "$ext_id" 1
			dconf update
		fi
	fi
}

function gsettings_set_global_value {
	#TODO
	logmkdir /etc/dconf/profile
	textfile /etc/dconf/profile/user "user-db:user
system-db:local" root
#TODO: 1. Read the old value and see if it has to be changed
			
	textfile /etc/dconf/db/local.d/00-extensions:
}
