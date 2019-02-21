#!/bin/bash
/bin/sleep 1

function try_mount {
	local device=$1
	local klucz=$2
	local mount_point=$3
	local name=$4
	if [ -f "${klucz}" ]; then
		if ! sudo dmsetup ls | grep $name; then
			if ! /sbin/cryptsetup luksOpen --key-file "$key" "$device" $name; then
				return -1
			fi
		fi
		if ! mount -l | grep " on ${mount_point} "; then
			if ! /bin/mount -t btrfs -o compress,rw,noacl,noatime,autodefrag,ssd  /dev/mapper/${name} "${mount_point}"; then
				return -1
			fi
			/bin/chmod 0775 ${mount_point}
		fi
	else
		if mount -l | grep " on ${mount_point} "; then
			if ! /bin/umount -lf "${mount_point}"; then
				return -1
			fi
		fi		
		if sudo dmsetup ls | grep $name; then
			if ! /sbin/cryptsetup luksClose $name; then
				return -1
			fi
		fi
	fi
}

for file in /usr/local/lib/adam/mounter/*.link; do
	read -r name device klucz mount_point < "$file"
	try_mount $device $klucz $mount_point $name
done

/bin/sync

