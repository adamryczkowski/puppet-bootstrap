#!/bin/bash

# Function tries to mount the local cache
function mount_network_cache {
   local mountpoint=$1
   local smb_server=$2
   if [[ "$mountpoint" == "" ]]; then
      mountpoint=/media/adam-minipc/other
   fi
   if [[ "$smb_server" == "" ]]; then
      smb_server=adam-minipc
   fi
   mount_smb_share $mountpoint $smb_server
}

function smb_share_client {
	local server=$1
	local remote_name=$2
	local local_path=$3
	local credentials_file=$4
	local extra_opt=$5
	if [ "${credentials_file}" == "auto" ]; then
		credentials_file="/etc/samba/user"
	fi
	if [ -n "${extra_opt}" ]; then
		extra_opt=",${extra_opt}"
	fi
	fstab_entry "//${server}/${remote_name}" ${local_path} cifs users,credentials=${credentials_file},noexec,noauto${extra_opt} 0 0
}

function mount_smb_share {
	local mountpoint=$1
	local smbserver=$2
	if is_host_up $2; then
	   mount_dir $1
	   return $?
	fi
	return 1
}

function mount_dir {
	local mountpoint=$1
	if [ ! -d "$mountpoint" ]; then
	   if is_mounted "" $mountpoint; then
	      return 0
	   fi
		while [ ! -d "$mountpoint" ]; do
			mountpoint=$(dirname "$mountpoint")
		done
		logexec mount "$mountpoint"
		return $?
	fi
	return 1
}

function fstab_entry {
	local spec=$1
	local file=$2
	local vfstype=$3
	local opt=$4
	local dump=$5
	local passno=$6
	install_apt_package augeas-tools augtool
	logheredoc EOT
	cat >/tmp/fstab.augeas<<EOT
#!/usr/bin/augtool -Asf

# The -A combined with this makes things much faster
# by loading only the required lens/file
transform Fstab.lns incl /etc/fstab
load

# $noentry will match /files/etc/fstab only if the entry isn't there yet
defvar noentry /files/etc/fstab[count(*[file="${file}"])=0]

# Create the entry if it's missing
set \$noentry/01/spec "${spec}"
set \$noentry/01/file "${file}"

# Now amend existing entry or finish creating the missing one
defvar entry /files/etc/fstab/*[file="${file}"]

set \$entry/spec "${spec}"
set \$entry/vfstype "${vfstype}"
rm \$entry/opt

EOT
	OLDIFS="$IFS"
	export IFS=","
	local i=1
	pattern='^([^=]+)=(.*)$'
	for entry in $opt; do
		if [ "$i" == "1" ]; then
			echo "ins opt after \$entry/vfstype">>/tmp/fstab.augeas
		else
			echo "ins opt after \$entry/opt[last()]">>/tmp/fstab.augeas
		fi
		if [[ "${entry}" =~ $pattern ]]; then
			lhs=${BASH_REMATCH[1]}
			rhs=${BASH_REMATCH[2]}
			echo "set \$entry/opt[last()] \"$lhs\"">>/tmp/fstab.augeas
			echo "set \$entry/opt[last()]/value \"${rhs}\"">>/tmp/fstab.augeas
		else
			echo "set \$entry/opt[last()] \"$entry\"">>/tmp/fstab.augeas
		fi
		let "i=i+1"
	done
	export IFS="$OLDIFS"
	echo "set \$entry/dump \"${dump}\"">>/tmp/fstab.augeas
	echo "set \$entry/passno \"${passno}\"">>/tmp/fstab.augeas
	logexec sudo /usr/bin/augtool -Asf /tmp/fstab.augeas
	
}

#Iterates over all devices managed by dmsetup and returns true, if found the device with the given path
function find_device_in_dmapper {
	local target="$1"
	local pattern1='^([^ ]+ +)'
	local pattern2='device: *()[^ ]+)$'
	local line
	local device
	local backend
	sudo dmsetup ls | while read line; do
		if [[ "$line" =~ $pattern1 ]]; then
			device=${BASH_REMATCH[1]}
			backend=$(sudo cryptsetup status $device | grep -F "device:")
			if [[ "${backend}" =~ $pattern2 ]]; then
				device=${BASH_REMATCH[1]}
				if [ "$device" == "$target" ]; then
					echo "$device"
					return 0
				fi
			fi
		else
			errcho "Syntax error of the output of dmsetup."
		fi
	done
	return -1 #not found
}

function is_mounted {
	local device=$1
	local mountpoint=$2
	if [ -n "$device" ] && [ -n "$mountpoint" ]; then
		ans=$(mount | grep -F "${device} on ${mountpoint}")
	elif [ -n "$device" ]; then
		ans=$(mount | grep -F "${device} on ")
	elif [ -n "$mountpoint" ]; then
		ans=$(mount | grep -F " on ${mountpoint}")
	else
		errcho "is_mounted called with no arguments"
		return -1
	fi
	if [ "$ans" != "" ]; then
		return 0
	else
		return -1
	fi
}

function find_device_from_mountpoint {
	local mountpoint="$1"
	local pattern="^(.*) on (${mountpoint}) type "
	local ans
	ans=$(mount | grep -E " on ${mountpoint} ")
	if [[ "$ans" =~ $pattern ]]; then
		echo "${BASH_REMATCH[1]}"
		return 0
	fi
	return -1
}

#Gets the backing device from the dm device if it uses cryptsetup
function device_from_crypt_dmapper {
	local dmdevice=$1
	local pattern='device: *([^ ]+)$'
	local backend_line=$(sudo cryptsetup status "/dev/mapper/${dmdevice}" | grep -F "device:")
	if [[ "$backend_line" =~ $pattern ]]; then
		echo "${BASH_REMATCH[1]}"
		return 0
	else
		echo ""
		return -1
	fi
}

function backing_luks_device_from_mount_point {
	local mountpoint="$1"
	local pattern='^/dev/mapper/(.*)$'
	local actual_dmdevice=$(find_device_from_mountpoint "${mount_point}")
	if [ -n "${actual_dmdevice}" ]; then
		if [[ "$actual_dmdevice" =~ $pattern ]]; then
			local actual_dmdevice="${BASH_REMATCH[1]}"
			local actual_device=device_from_crypt_dmapper ${actual_dmdevice}
			if [ -n "${actual_device}" ]; then
				echo "$actual_device"
				return 0
			else
				errcho "The device mounted under ${mount_point} is not Luks. Exiting."
				return 3
			fi
		else
			errcho "Something else is mounted under ${mount_point}. Exiting."
			return 2
		fi
	else
		errcho "Mount point not found. Exiting."
		return 1
	fi
}
