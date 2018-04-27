#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Prepares an Ubuntu installation with common tweaks.

Usage:

$(basename $0) [-r|--release <ubuntu release>] [--user <name of user>]
			[--tweaks <comma separated sets of tweaks]
			[--repo-path <repo-path>]
			[--help] [--debug] [--log <output file>]

where

 --tweaks                 - Name of the tweaks. Currently implemented:
                               - cli (htop, byobu, liquidprompt, etc.)
                               - nemo (nemo3)
                               - smb (smb shares the connect to my media servers)
                               - mod3 (switching workspaces with mod3 key)
                               - kodi
                               - office2007
                               - docs
 --user <user name>       - Name of user. If specified, some extra user-specific tasks
                            will be performed for most of the tricks.
 --repo-path              - Path to the repository. Some tweaks require it.
 -r|--release             - Ubuntu release to be tweaked. 
                            Currently supports only 16.04/xenial, so this option is meaningless.
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands


Example:

./$(basename $0) --tweaks cli,nemo,smb,mod3,kodi,office2007,bumblebee,laptop
"

dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}
mypath=${0%/*}
mypath=`dir_resolve $mypath`
cd $mypath

repo_path=/media/adam-minipc/other/debs
release=xenial
user=$USER
common_debug=0

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--tweaks)
	if [ -z "$tweaks" ]; then
		tweaks=$1
	else
		tweaks=${tweaks},$1
	fi
	shift
	;;
	--repo-path)
	repo_path="$1"
	shift
	;;
	--user)
	user="$1"
	shift
	;;
	-r|--release)
	release=$1
	shift
	;;
	--log)
	log=$1
	shift
	;;
	--debug)
	common_debug=1
	;;
	--help)
	echo "$usage"
	exit 0
	;;
	-*)
	echo "Error: Unknown option: $1" >&2
	echo "$usage" >&2
	;;
esac
done

if [ -z "$tweaks" ]; then
	echo "$usage"
	exit 0
else
	tweaks="tweak_base,${tweaks}"
fi

home=$(get_home_dir)

if [ -n "$common_debug" ]; then
	if [ -z "$log" ]; then
		log=/dev/stdout
	fi
fi

#Makes sure basic scripts are installed
function tweak_base  {
	install_script files/discover_session_bus_address.sh
	install_apt_packages git
}

function desktop {
	install_apt_packages meld chromium-browser gparted
	gsettings_remove_from_array com.canonical.Unity.Launcher favorites 'application://org.gnome.Software.desktop'
	gsettings_remove_from_array com.canonical.Unity.Launcher favorites 'application://ubuntu-amazon-default.desktop'
	gsettings_set_value org.compiz.unityshell:/org/compiz/profiles/unity/plugins/unityshell/ launcher-hide-mode 1
	gsettings_set_value org.gnome.desktop.peripherals.touchpad scroll-method edge-scrolling
	gsettings_set_value org.gnome.desktop.screensaver lock-enabled false
	gsettings_set_value org.gnome.desktop.screensaver ubuntu-lock-on-suspend false
	gsettings_set_value com.canonical.Unity integrated-menus true
}

function laptop {
	install_apt_packages redshift_gtk
}

function bumblebee {
	add_ppa graphics-drivers/ppa
	do_update
	logexec sudo ubuntu-drivers autoinstall
}

function cli {
	tweak_base
	install_apt_packages git htop liquidprompt nethogs iftop iotop mc byobu openssh-server
	logexec liquidprompt_activate
	logexec sudo liquidprompt_activate
	home=$(get_home_dir)
	logmkdir ${home}/tmp
	get_git_repo https://github.com/adamryczkowski/update-all ${home}/tmp
}

function nemo {
	add_ppa ppa:webupd8team/nemo3
	do_update
	install_apt_package nemo nemo

	gsettings_set_value org.gnome.desktop.background show-desktop-icons false
	xdg-mime default nemo.desktop inode/directory application/x-gnome-saved-search
	gsettings_remove_from_array com.canonical.Unity.Launcher favorites 'application://org.gnome.Nautilus.desktop'
	gsettings_add_to_array com.canonical.Unity.Launcher favorites 'application://nemo.desktop' 1
	gsettings_set_value org.nemo.preferences show-open-in-terminal-toolbar true
	gsettings_set_value org.nemo.preferences default-folder-viewer "compact-view"
	gsettings_set_value org.nemo.preferences show-hidden-files true
}

function smb {
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
		echo "CURRENT i:$i"
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

oldifs=${IFS}
export IFS=","
for tweak in $tweaks; do
	export IFS=${oldifs}
	echo "Current tweak: ${tweak}"
	${tweak}
	export IFS=","
done
export IFS=${oldifs}

