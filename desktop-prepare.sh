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
	add_ppa fixnix/netspeed
	add_ppa yktooo/ppa
	install_apt_packages meld chromium-browser gparted indicator-netspeed-unity indicator-sound-switcher
	gsettings_remove_from_array com.canonical.Unity.Launcher favorites 'application://org.gnome.Software.desktop'
	gsettings_remove_from_array com.canonical.Unity.Launcher favorites 'application://ubuntu-amazon-default.desktop'
	gsettings_set_value org.compiz.unityshell:/org/compiz/profiles/unity/plugins/unityshell/ launcher-hide-mode 1
	gsettings_set_value org.gnome.desktop.peripherals.touchpad scroll-method edge-scrolling
	gsettings_set_value org.gnome.desktop.screensaver lock-enabled false
	gsettings_set_value org.gnome.desktop.screensaver ubuntu-lock-on-suspend false
	gsettings_set_value com.canonical.Unity integrated-menus true
	
	install_apt_package_file skypeforlinux-64.deb skypeforlinux "https://go.skype.com/skypeforlinux-64.deb"
}

function blender {
	install_dir="/opt/blender"
	if [ ! -f "${install_dir}/blender" ]; then
		file="BlenderFracture-2.79a-linux64-glibc219.tar.xz"
		file_path=$(get_cached_file "${file}" http://blenderphysics.com/?ddownload=4225)
		install_apt_packages xz-utils
		logmkdir /opt/blender
		logexec sudo tar xf ${file_path} -C ${install_dir}
	fi
}

function office2007 {
	echo "#TODO"
	release_key=$(get_cached_file WineHQ_Release.key https://dl.winehq.org/wine-builds/Release.key)
	logexec sudo apt-key add "${release_key}"
	add_apt_source_manual winehq 'deb https://dl.winehq.org/wine-builds/ubuntu/ xenial main'
	
	release_key=$(get_cached_file PlayOnLinux_Release.key http://deb.playonlinux.com/public.gpg)
	logexec sudo apt-key add "${release_key}"
	add_apt_source_manual playonlinux 'deb http://deb.playonlinux.com/ xenial main'
	
	do_update
	install_apt_package winehq-devel playonlinux
}

function laptop {
	install_apt_packages redshift_gtk
	desktop
}

function bumblebee {
	return 1 #not ready
	add_ppa graphics-drivers/ppa
	add_ppa bumblebee/testing
	install_apt_package_file "cuda-repo-ubuntu1604_9.1.85-1_amd64.deb" "cuda-repo-ubuntu1604" http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/cuda-repo-ubuntu1604_9.1.85-1_amd64.deb
	if [ "$?" == "0" ]; then
		logexec sudo apt-key adv --fetch-keys http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/7fa2af80.pub
	fi
	
	do_update
	
	logexec sudo ubuntu-drivers autoinstall
	nvidia_package=$(apt list --installed |grep -E 'nvidia-[0-9]+/')
	pattern='nvidia-([0-9]+)/'
	if [[ "${nvidia_package}" =~ $pattern ]]; then
		nvidia_version=${BASH_REMATCH[1]}
	else
		errcho "Unexpected error"
		exit 1
	fi
	#TODO: https://gist.github.com/whizzzkid/37c0d365f1c7aa555885d102ec61c048
}

function cli {
	tweak_base
	install_apt_packages git htop liquidprompt nethogs iftop iotop mc byobu openssh-server
	logexec liquidprompt_activate
	logexec sudo liquidprompt_activate
	home=$(get_home_dir)
	logmkdir ${home}/tmp
	get_git_repo https://github.com/adamryczkowski/update-all ${home}/tmp
	#youtube-dl
}

function rdesktop {
	reposerver="$(dirname ${repo_path})/r-mirror"
	$mypath/prepare-R-node.sh --rstudio --repo-server file://${reposerver} --deb-folder ${repo_path} --debug
}

function virtualbox {
	release_key=$(get_cached_file Oracle_2016_Release.key https://www.virtualbox.org/download/oracle_vbox_2016.asc)
	logexec sudo apt-key add "${release_key}"
	release_key=$(get_cached_file Oracle_Release.key https://www.virtualbox.org/download/oracle_vbox.asc)
	logexec sudo apt-key add "${release_key}"
	add_apt_source_manual winehq 'deb https://download.virtualbox.org/virtualbox/debian xenial contrib'
	add_ppa thebernmeister/ppa
	install_apt_packages virtualbox-5.2 indicator-virtual-box
	
	if ! VBoxManage list extpacks | grep "Oracle VM VirtualBox Extension Pack" >/dev/null; then
		version=$(VBoxManage -v)
		echo $version
		var1=$(echo $version | cut -d 'r' -f 1)
		echo $var1
		var2=$(echo $version | cut -d 'r' -f 2)
		echo $var2
		virtualbox_extension="Oracle_VM_VirtualBox_Extension_Pack-$var1-$var2.vbox-extpack"
	
		virtualbox_extension=$(get_cached_file ${virtualbox_extension} http://download.virtualbox.org/virtualbox/$var1/$virtualbox_extension)
	
		#sudo VBoxManage extpack uninstall "Oracle VM VirtualBox Extension Pack"
		$loglog
		echo "y" |sudo VBoxManage extpack install ${virtualbox_extension} --replace
	fi
	homedir=$(get_home_dir)
	if [ ! -f "${homedir}/.config/autostart/indicator-virtual-box.py.desktop" ]; then
		logexec cp /usr/share/applications/indicator-virtual-box.py.desktop "${homedir}/.config/autostart/indicator-virtual-box.py.desktop"
	fi
}

function kodi {
	add_ppa ppa:team-xbmc/ppa
	install_apt_package kodi
	home="$(get_home_dir)"
	logmkdir "${home}/.kodi/userdata" ${USER}
	textfile "${home}/.kodi/userdata/advancedsettings.xml" "\
<advancedsettings>
  <videodatabase>
    <type>mysql</type>
    <host>192.168.10.8</host>
    <port>3306</port>
    <user>kodi</user>
    <pass>kodi</pass>
  </videodatabase> 
  <musicdatabase>
    <type>mysql</type>
    <host>192.168.10.8</host>
    <port>3306</port>
    <user>kodi</user>
    <pass>kodi</pass>
  </musicdatabase>
  <videolibrary>
    <importwatchedstate>true</importwatchedstate>
    <importresumepoint>true</importresumepoint>
  </videolibrary>
</advancedsettings>"
	textfile "${home}/.kodi/userdata/passwords.xml" "\
<passwords>
    <path>
        <from pathversion="1">smb://ADAM-990FX/rozne</from>
        <to pathversion="1">smb://adam:Zero%20tolerancji@ADAM-990FX/rozne/</to>
    </path>
</passwords>"
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
		foldername=$(basename ${folder})
		gsettings_add_to_array com.canonical.Unity.Devices blacklist ${foldername}
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
		foldername=$(basename ${folder})
		gsettings_add_to_array com.canonical.Unity.Devices blacklist ${foldername}
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

