#!/bin/bash
cd `dirname $0`
. ./common.sh

usage="
Creates and manages encrypted storage for documents


Usage:

$(basename $0) keygen <key filename>
               [--debug] [--log <output file>] 

$(basename $0) format [--device <device> | --file <file_backend> --size <size>] --key <key filename> 
               [--user <username> --user-docs-prefix <doc-path>]
               [--debug] [--log <output file>] 

$(basename $0) setup <device>|<file_backend> --key <key filename> [--user <username>] --user-docs-prefix <doc-path>
               [--debug] [--log <output file>] 


keygen creates new key. Remember to backup it!
format creates new LUKS device from scratch. If device exists, it will refuse to act.
setup  integrates the device with the user. It will create links to /home/user for Desktop, Documents, Music, Videos, bin etc. 
       It will also create a script that mounts the device upon login.

where:
 <key filename>                - Path to the key file used by LUKS device. Relative to the user's home.
 <device>                      - Block device to use as a backing for the storage. 
 <file_backend>                - Path to the file where the device will be backed. Requires --size paramenter.
 <size>                        - Size of the device. Valid only if device is a filename.
 --user <username>             - Username to integrate with the documents. Defaults to the current user.
 --user-docs-prefix <doc-path> - Prefix path to the user's folder in the documents. E.g. 'Adam' or ''. 
 --debug                       - Flag that sets debugging mode. 
 --log                         - Path to the log file that will log all meaningful commands

Examples:

$(basename $0) keygen klucz.bin 
$(basename $0) format /dev/sda5 --key klucz.bin --user-docs-prefix Adam
$(basename $0) format /mnt/ext4/docs.bin --key klucz.bin --size 140G
$(basename $0) setup /dev/sda5 --key klucz.bin --user-docs-prefix Adam --user adam
"

if [ -z "$1" ]; then
	echo "$usage" >&2
	exit 0
fi

set -x

mode="$1"
shift

if [ "$mode" != "keygen" ] && [ "$mode" != "format" ] && [ "$mode" != "setup" ]; then
	errcho "Unkown mode. First argument must be format, keygen or setup."
	echo "$usage"
	exit 1
fi

user="$USER"



function keygen {
	key="$1"
	if [ -z "$key" ]; then
		echo "Error: No path to the key. First argument must be a path (can be relative to the $HOME)" >&2
		echo "$usage" >&2
		exit 1
	fi
	shift
	
	while [[ $# > 0 ]]; do
	arg="$1"
	shift

	case $arg in
		--debug)
		debug=1
		;;
		--log)
		log=$1
		shift
		;;
		--help)
		echo "$usage"
		exit 0
		;;
		-*)
		echo "Error: Unknown option: $1" >&2
		echo "$usage" >&2
		exit 1
		;;
	esac
	done
	
	if [[ ! "$key" = /* ]]; then
		key="${HOME}/${key}"
	fi
	if [ -f "$key" ]; then
		errcho "Error: The $key already exists. Overwriting it will destroy the old contents. If you insist to re-create it, first erase it with\n    sudo rm \"$key\""
		exit 1
	fi
	if [ ! -w "$key" ]; then
		use_sudo="sudo "
	else
		use_sudo=""
	fi
	
	echo "Creating new key on $key..."
	logexec $use_sudo dd if=/dev/random of="$key" bs=512 count=1
}

function format {
	device="$1"
	if [ -z "$device" ]; then
		echo "Error: No device. First argument must be a device" >&2
		echo "$usage" >&2
		exit 1
	fi
	shift
	
	while [[ $# > 0 ]]; do
	arg="$1"
	shift

	case $arg in
		--debug)
		debug=1
		;;
		--log)
		log=$1
		shift
		;;
		--help)
		echo "$usage"
		exit 0
		;;
		--key)
		key=$1
		shift
		;;
		--size)
		size=$1
		shift
		;;
		--device)
		device=$1
		use_block=1
		shift
		;;
		--file)
		device=$1
		use_block=0
		shift
		;;
		--user)
		user="$1"
		shift
		;;
		--user-docs-prefix)
		user_docs_prefix="$1"
		shift
		;;
		-*)
		echo "Error: Unknown option: $1" >&2
		echo "$usage" >&2
		exit 1
		;;
	esac
	done
	
	if [[ ! "$key" = /* ]]; then
		home=$(get_home_dir $user)
		key="${home}/${key}"
	fi
	if [! -f "$key" ]; then
		errcho "Error: There is no key in $key. Please specify a path (can be relative to $HOME) with the key. The key can be any random bytes. Only first 512 bytes will be used."
		exit 1
	fi
	
	if [ -n "$use_block" ]; then
		errcho "Error: No backing device. You must provide either --file or --device argument."
		exit 1
	fi
	
	
	if [ "$use_block" == "1" ]; then
		if [ ! -b "$device" ]; then
			errcho "Error: The device $device is not an existing block device."
			exit 1
		fi
		if cryptsetup isLuks "$device"; then
			errcho "Error: The device is already formatted as LUKS device. If you insist to re-format it, first erase this device with\n    sudo cryptsetup luksErase $device"
			exit 1
		fi
		if [ -n $size ]; then
			echo "Size of the device will be ignored, because file already exists." >&2
		fi
	else
		if [ -f "$device" ]; then
			errcho "Error: The file backing for the device already exists. If you insist to re-create it, first erase it with\n    sudo rm \"$device\""
			exit 1
		fi
		if [ -z $size ]; then
			echo "Unknown size of the file backing device. Specify the size using --size argument." >&2
			exit 1
		fi
		parent_device=$(dirname "$device")
		logmkdir "$parent_device"
		logexec sudo dd if=/dev/zero of="$device" bs=1 count=1 seek=$size
	fi
	
	logexec sudo cryptsetup luksFormat -q --key-file "$key" --cipher aes-xts-plain --size 512 "$device"
	tmpdir=$(mktemp)
	logmkdir "$tmpdir"
	logexec sudo cryptsetup luksOpen --key-file "$key" "$device" "$(basename $tmpdir)" 
	logexec sudo mkfs.btrfs /dev/mapper/"$(basename $tmpdir)"
	
	if [ -n "$user_docs_prefix" ]; then
		logexec sudo mount /dev/mapper/"$(basename $tmpdir)" "$tmpdir" -o=noatime,compress
		logexec sudo chown $user "$tmpdir"
		logmkdir "${tmpdir}/${user_docs_prefix}/MyDocs" $user
		logmkdir "${tmpdir}/${user_docs_prefix}/Desktop" $user
		logmkdir "${tmpdir}/${user_docs_prefix}/linux/bin" $user
		logmkdir "${tmpdir}/${user_docs_prefix}/linux/debs" $user
		logmkdir "${tmpdir}/${user_docs_prefix}/linux/Downloads" $user
		logmkdir "${tmpdir}/${user_docs_prefix}/linux/Videos" $user
		logmkdir "${tmpdir}/${user_docs_prefix}/linux/Music" $user
		logmkdir "${tmpdir}/${user_docs_prefix}/Firefox profiles" $user
		logmkdir "${tmpdir}/${user_docs_prefix}/Firefox Scrapbook" $user
		logmkdir "${tmpdir}/${user_docs_prefix}/Firefox Sessions" $user
		logmkdir "${tmpdir}/${user_docs_prefix}/Poczta" $user
		logmkdir "${tmpdir}/${user_docs_prefix}/Unison" $user
		logmkdir "${tmpdir}/${user_docs_prefix}/Thunderbird profiles" $user
	fi
}

function link_folder {
	mode=$1
	dest="$2"
	user="$3"
	
	source=$(get_special_dir $mode $user)
	if [ "$source" != "" ]; then
		if [ -d "$source" ] && [ -d $dest ]; then
			tmpname=$(mktemp -d --dry-run "${source}.XXX")
			if [ ! -L "$source" ]; then
				if [ -n "$(ls -A "${source}")" ]; then
					logexec sudo -u $user mv "$source/*" "$dest/" --update
					if [ -n "$(ls -A "${source}")" ]; then
						logexec sudo -u $usermv "$source" "$tmpname"
					else
						logexec sudo -u $user rmdir "$source"
					fi
				fi
			else
				if [ "$(readlink "$source")" != "$dest" ]; then
					logexec sudo -u $user mv "$source" "${source}.bak"
				else
					return
				fi
			fi
			logexec sudo -u $user ln -s "${dest}" "${source}"
		fi
	fi
}

function setup {
	mount_point="/home/Docs"
	device="$1"
	if [ -z "$device" ]; then
		echo "Error: No device. First argument must be a device" >&2
		echo "$usage" >&2
		exit 1
	fi
	shift
	
	while [[ $# > 0 ]]; do
	arg="$1"
	shift
	case $arg in
		--debug)
		debug=1
		;;
		--log)
		log=$1
		shift
		;;
		--help)
		echo "$usage"
		exit 0
		;;
		--key)
		key=$1
		shift
		;;
		--user)
		user="$1"
		shift
		;;
		--user-docs-prefix)
		user_docs_prefix="$1"
		shift
		;;
		--mount-point)
		mount_point="$1"
		shift
		;;
		-*)
		echo "Error: Unknown option: $1" >&2
		echo "$usage" >&2
		exit 1
		;;
	esac
	done
	
	mounted=0
	if is_mounted "" "$mount_point"; then
		actual_dmdevice=$(find_device_from_mountpoint "${mount_point}")
		if [ -n "${actual_dmdevice}" ]; then
			pattern='^/dev/mapper/(.*)$'
			if [[ "$actual_dmdevice" =~ $pattern ]]; then
				actual_dmdevice="${BASH_REMATCH[1]}"
				actual_device=$(device_from_crypt_dmapper "${actual_dmdevice}")
				if [ -n "${actual_device}" ]; then
					if [ "${actual_device}" != "$device" ]; then
						errcho "Different documents are mounted right now. Exiting."
						exit 1
					else
						mounted=1
					fi
				else
					errcho "The device mounted under ${mount_point} is not Luks. Exiting."
					exit 3
				fi
			else
				errcho "Something else is mounted under ${mount_point}. Exiting."
				exit 2
			fi
		else
			errcho "Internal error. Exiting."
			exit -1
		fi
	fi
	
	if [[ ! "$key" = /* ]]; then
		home=$(get_home_dir $user)
		key="${home}/${key}"
	fi
	if [ ! -f "$key" ]; then
		errcho "Error: There is no key in $key. Please specify a path (can be relative to $HOME) with the key. The key can be any random bytes. Only first 512 bytes will be used."
		exit 1
	fi
	
	logmkdir /usr/local/lib/adam/mounter
	textfile /usr/local/lib/adam/mounter.sh "#!/bin/bash
/bin/sleep 1
/sbin/cryptsetup luksOpen --key-file \"$key\" \"$device\" crypt-docs
/bin/mount -t btrfs -o compress,rw,noacl,noatime,autodefrag,ssd  /dev/mapper/crypt-docs \"$mount_point\"
/bin/chmod 0775 /home/Docs
/bin/sync" 
	logexec sudo chmod +x /usr/local/lib/adam/mounter.sh
	
	if [ "$mounted" == "0" ]; then
		logmkdir "$mount_point"
		logexec /usr/local/lib/adam/mounter.sh
		
		if ! backing_luks_device_from_mount_point "${mount_point}"; then
			errcho "Something wrong while mounting the ${mount_point}. Exiting."
		fi
	fi
	
	release=$(get_ubuntu_codename)
	if [ "$release" == "bionic" ]; then
		echo "TODO"
		#TODO: dodać do skryptów uruchamianych podczas logowania
	else
		linetextfile /etc/pam.d/common-session "session optional	pam_exec.so	/bin/sh /usr/local/lib/adam/mounter.sh"
	fi
	if [ -n "$user_docs_prefix" ]; then
		user_docs_prefix="${mount_point}/${user_docs_prefix}"
		link_folder DESKTOP "${user_docs_prefix}/Desktop" $user
		link_folder DOWNLOAD "${user_docs_prefix}/linux/Downloads" $user
		link_folder DOCUMENT "${user_docs_prefix}/MyDocs" $user
		link_folder MUSIC "${user_docs_prefix}/linux/Music" $user
		link_folder VIDEO "${user_docs_prefix}/linux/Videos" $user
		link_folder PICTURE "${user_docs_prefix}/linux/Pictures" $user
	fi
}


if [ "$mode" == "keygen" ]; then
	keygen "$@"
fi

if [ "$mode" == "format" ]; then
	format "$@"
fi

if [ "$mode" == "setup" ]; then
	setup "$@"
fi

