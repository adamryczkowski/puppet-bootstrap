#!/bin/bash
cd `dirname $0`
. ./common.sh

cd '/home/adam/tmp/puppet-bootstrap'

repo_path=/media/adam-minipc/other/debs
release=xenial
user=$USER
common_debug=0
tweaks=smb

tweaks="tweak_base,${tweaks}"

echo "DSDSD"
echo "DSDSD"
echo "DSDSD"
#fstab_entry //adam-minipc/download /media/adam-minipc/download cifs users,credentials=/etc/samba/user,noexec 0 0
#smb_share_client adam-minipc download /media/adam-minipc/download /etc/samba/user
echo "DSDSD"
echo "DSDSD"
echo "DSDSD"


#Makes sure basic scripts are installed
function tweak_base() {
	install_script files/discover_session_bus_address.sh
	install_apt_packages git
}

function desktop() {
	install_apt_packages meld
	gsettings_remove_from_array com.canonical.Unity.Launcher favorites 'application://org.gnome.Software.desktop'
	gsettings_remove_from_array com.canonical.Unity.Launcher favorites 'application://ubuntu-amazon-default.desktop'
	#Autoukrywanie paska
	#touchpad prawy margines
}

function cli() {
	tweak_base
	install_apt_packages git htop liquidprompt nethogs iftop iotop mc byobu openssh-server
	logexec liquidprompt_activate
	logexec sudo liquidprompt_activate
}

function nemo() {
	add_ppa webupd8team/nemo3
	do_update
	install_apt_package nemo nemo

	gsettings_set_value org.gnome.desktop.background show-desktop-icons false
	xdg-mime default nemo.desktop inode/directory application/x-gnome-saved-search
	gsettings_remove_from_array com.canonical.Unity.Launcher favorites 'application://org.gnome.Nautilus.desktop'
	#usuń nautilus z paska
	#pokaż ukryte pliki
}

function smb() {
	install_apt_package cifs-utils
	textfile /etc/samba/user "username=adam
	password=Zero tolerancji"

	declare -a folders=("wielodysk/filmy" "wielodysk/niezbednik" "wielodysk/docs" "wielodysk/public" "wielodysk/zdjecia")
	declare -a shares=("rozne" "smiecie" "docs" "public" "zdjecia")
	host=adam-990fx

	local i=1
	arraylength=${#folders[@]}
	for (( i=1; i<${arraylength}+1; i++ )); do
		folder=/media/${folders[$i-1]}
		share=${shares[$i-1]}
		logmkdir ${folder}
		smb_share_client ${host} ${share} ${folder} /etc/samba/user
	done

	declare -a folders=("adam-minipc/download" "adam-minipc/other" "adam-minipc/unfinished" "adam-minipc/videos")
	declare -a shares=("download" "other" "partial" "videos")
	host=adam-minipc

	local i=1
	arraylength=${#folders[@]}
	for (( i=1; i<${arraylength}+1; i++ )); do
		folder=/media/${folders[$i-1]}
		share=${shares[$i-1]}
		logmkdir ${folder}
		smb_share_client ${host} ${share} ${folder} /etc/samba/user
	done
}

smb
exit 1

local oldifs=${IFS}
export IFS=","
for tweak in $tweaks; do
	export IFS=${oldifs}
	echo "Current tweak: ${tweak}"
	$(${tweak})
	export IFS=","
done
export IFS=${oldifs}
