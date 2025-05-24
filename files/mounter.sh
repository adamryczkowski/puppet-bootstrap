#!/bin/bash
#/bin/sleep 1

function try_mount() {
	local device=/dev/disk/by-uuid/$1
	#	local device=$(readlink /dev/disk/by-uuid/$1)
	local klucz=$2
	local mount_point=$3
	local name=$4
	local user=$5
	#    if [ -f "${klucz}" ]; then
	if ! sudo dmsetup ls | grep $name>/dev/null; then
		if ! sudo cryptsetup luksOpen --key-file ${klucz} ${device} ${name}; then
			return -1
		fi
	fi
	mkdir -p ${mount_point}
	if ! mount -l | grep " on ${mount_point} ">/dev/null; then
		/bin/mount -t btrfs -o compress,rw,noacl,noatime,autodefrag,ssd  /dev/mapper/$name ${mount_point}
		/bin/chown ${user} ${mount_point}
		/bin/chmod 0775 ${mount_point}
	fi
}

for file in /usr/local/lib/mounter/*.link; do
	read -r name device klucz mount_point user < "$file"
	try_mount $device $klucz $mount_point $name $user
done

/bin/sync
