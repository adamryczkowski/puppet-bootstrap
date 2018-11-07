#!/bin/bash

## dependency: prepare_R-node.sh

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
                               - desktop (common Ubuntu desktop applications)
                               - blender
                               - bumblebee
                               - nvidia (installs latest nvidia drivers + cuda)
                               - rdesktop (R desktop)
                               - virtualbox
                               - smb (smb shares the connect to my media servers)
                               - mod3 (switching workspaces with mod3 key)
                               - kodi
                               - office2007
                               - docs
                               - gedit (gedit plugins)
 --user <user name>       - Name of user. If specified, some extra user-specific tasks
                            will be performed for most of the tricks.
 --repo-path              - Path to the repository. Some tweaks require it.
 -r|--release             - Ubuntu release to be tweaked. 
                            Currently supports only 16.04/xenial, so this option is meaningless.
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands


Example:

./$(basename $0) --tweaks cli,nemo,smb,mod3,kodi,office2007,bumblebee,desktop,blender,laptop,zulip,owncloud,gedit
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
	install_apt_packages git gdebi-core
	mount_smb_share "$repo_path"
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
	
	release=$(get_ubuntu_codename)
	if [ "$release" == "bionic" ]; then
		install_apt_package gnome-tweak-tool
		ext_path=$(get_cached_file "gnome_extensions/workspace-grid-for-3.16-to-3.26.zip" "https://github.com/zakkak/workspace-grid/releases/download/v1.4.1/workspace-grid-for-3.16-to-3.26.zip")
		install_gnome_extension ${ext_path}
		
		gsettings_set_value org.gnome.shell.extensions.workspace-grid num-rows 3
		gsettings_set_value org.gnome.mutter dynamic-workspaces false
		gsettings_set_value org.gnome.shell.extensions.dash-to-dock dock-fixed false
	fi
	gsettings_set_value org.gnome.desktop.wm.preferences num-workspaces 9
	install_apt_package_file skypeforlinux-64.deb skypeforlinux "https://go.skype.com/skypeforlinux-64.deb"
	
	install_apt_packages redshift-gtk
	redshift-gtk &
}

function blender {
	install_dir="/opt/blender"
	if [ ! -f "${install_dir}/blender" ]; then
		if [ ! -d /opt/blender/blender_fracture_modifier ]; then
			file="BlenderFracture-2.79a-linux64-glibc219.tar.xz"
			file_path=$(get_cached_file "${file}" http://blenderphysics.com/?ddownload=4225)
			install_apt_packages xz-utils
			logmkdir /opt/blender
			logexec sudo tar xf ${file_path} -C ${install_dir}
		fi
		if [ -d /opt/blender/blender_fracture_modifier ]; then
			logexec sudo mv /opt/blender/blender_fracture_modifier/* /opt/blender
			logexec sudo rmdir /opt/blender/blender_fracture_modifier
		fi
	fi
	if [ ! -f "/opt/blender/blender.desktop" ]; then
		errcho "Something wrong with the Blender installation process. blender.desktop is missing."
	fi
	cp_file "/opt/blender/blender.desktop" /usr/share/applications/ root
	cp_file "/opt/blender/blender.svg" /usr/share/icons/hicolor/scalable/apps/ root
}

function office2007 {
	
	echo "#TODO"
#	release_key=$(get_cached_file WineHQ_Release.key https://dl.winehq.org/wine-builds/Release.key)
#	logexec sudo apt-key add "${release_key}"
	add_apt_source_manual winehq 'deb https://dl.winehq.org/wine-builds/ubuntu/ xenial main' https://dl.winehq.org/wine-builds/Release.key WineHQ_Release.key
	
#	release_key=$(get_cached_file PlayOnLinux_Release.key http://deb.playonlinux.com/public.gpg)
#	logexec sudo apt-key add "${release_key}"
	add_apt_source_manual playonlinux 'deb http://deb.playonlinux.com/ xenial main' http://deb.playonlinux.com/public.gpg PlayOnLinux_Release.key
	
	do_update
	install_apt_packages winehq-devel playonlinux
	
	add_group wine_office
	add_usergroup "$user" wine_office
	uncompress_cached_file office2007_pl.tar.xz "/opt/" "${user}:wine_office"
	local office_install="/opt/Office2007"
	chown_dir ${office_install} "$user" wine_office
	#Make sure all office is writable by anyone with execute permission preserverd
	chmod_dir ${office_install} 777 666 777
	
	install_script files/launch_office.sh /usr/local/bin/launch_office
	
	logmkdir "${home}/.PlayOnLinux/wineprefix"
	make_symlink ${office_install} "${home}/.PlayOnLinux/wineprefix/Office2007"
	
	textfile /usr/share/applications/excel.desktop "#!/usr/bin/env xdg-open
[Desktop Entry]
Name=Microsoft Excel
Exec=/usr/local/bin/launch_office excel %U
Type=Application
StartupNotify=true
Path=${office_install}/drive_c/Program Files/Microsoft Office/Office12
Icon=${office_install}/Microsoft Office Excel 2007
StartupWMClass=EXCEL.EXE
Terminal=false
MimeType=application/vnd.oasis.opendocument.spreadsheet;application/vnd.oasis.opendocument.spreadsheet-template;application/vnd.sun.xml.calc;application/vnd.sun.xml.calc.template;application/msexcel;application/vnd.ms-excel;application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;application/vnd.ms-excel.sheet.macroenabled.12;application/vnd.openxmlformats-officedocument.spreadsheetml.template;application/vnd.ms-excel.template.macroenabled.12;application/vnd.ms-excel.sheet.binary.macroenabled.12;text/csv;application/x-dbf;text/spreadsheet;application/csv;application/excel;application/tab-separated-values;application/vnd.lotus-1-2-3;application/vnd.oasis.opendocument.chart;application/vnd.oasis.opendocument.chart-template;application/x-dbase;application/x-dos_ms_excel;application/x-excel;application/x-msexcel;application/x-ms-excel;application/x-quattropro;application/x-123;text/comma-separated-values;text/tab-separated-values;text/x-comma-separated-values;text/x-csv;application/vnd.oasis.opendocument.spreadsheet-flat-xml;application/vnd.ms-works;application/clarisworks;application/x-iwork-numbers-sffnumbers;" root

	chmod_file /usr/share/applications/excel.desktop 0755

	textfile /usr/share/applications/powerpoint.desktop "#!/usr/bin/env xdg-open
[Desktop Entry]
Name=Microsoft Powerpoint
Exec=/usr/local/bin/launch_office powerpoint %U
Type=Application
StartupNotify=true
Path=${office_install}/drive_c/Program Files/Microsoft Office/Office12
Icon=${office_install}/Microsoft Office PowerPoint 2007
StartupWMClass=POWERPNT.EXE
Terminal=false
Name[en_US]=Microsoft PowerPoint" root

	chmod_file /usr/share/applications/powerpoint.desktop 0755
	
	textfile /usr/share/applications/word.desktop "#!/usr/bin/env xdg-open
[Desktop Entry]
Name=Microsoft Word
Exec=/usr/local/bin/launch_office word %U
Type=Application
StartupNotify=true
Path=${office_install}/drive_c/Program Files/Microsoft Office/Office12
Icon=${office_install}/Microsoft Office Word 2007
StartupWMClass=WINWORD.EXE
Terminal=false
Name[en_US]=Microsoft Word
MimeType=application/vnd.oasis.opendocument.text;application/vnd.oasis.opendocument.text-template;application/vnd.oasis.opendocument.text-web;application/vnd.oasis.opendocument.text-master;application/vnd.oasis.opendocument.text-master-template;application/vnd.sun.xml.writer;application/vnd.sun.xml.writer.template;application/vnd.sun.xml.writer.global;application/msword;application/vnd.ms-word;application/x-doc;application/x-hwp;application/rtf;text/rtf;application/vnd.wordperfect;application/wordperfect;application/vnd.lotus-wordpro;application/vnd.openxmlformats-officedocument.wordprocessingml.document;application/vnd.ms-word.document.macroenabled.12;application/vnd.openxmlformats-officedocument.wordprocessingml.template;application/vnd.ms-word.template.macroenabled.12;application/vnd.ms-works;application/vnd.stardivision.writer-global;application/x-extension-txt;application/x-t602;text/plain;application/vnd.oasis.opendocument.text-flat-xml;application/x-fictionbook+xml;application/macwriteii;application/x-aportisdoc;application/prs.plucker;application/vnd.palm;application/clarisworks;application/x-sony-bbeb;application/x-abiword;application/x-iwork-pages-sffpages;application/x-mswrite;application/x-starwriter;" root

	chmod_file /usr/share/applications/word.desktop 0755

}

function laptop {
	desktop
	gsettings_set_value org.gnome.desktop.peripherals.touchpad click-method "fingers"
	gsettings_set_value org.gnome.desktop.peripherals.touchpad edge-scrolling-enabled true
	gsettings_set_value org.gnome.desktop.peripherals.touchpad two-finger-scrolling-enabled false
	gsettings_set_value org.gnome.desktop.peripherals.touchpad scroll-method 'edge-scrolling'
	gsettings_set_value org.gnome.desktop.peripherals.touchpad tap-to-click true
	gsettings_set_value org.gnome.desktop.peripherals.touchpad natural-scroll false

}

function nvidia {
	add_ppa graphics-drivers/ppa
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
	install_apt_packages git htop liquidprompt nethogs iftop iotop mc byobu openssh-server silversearcher-ag
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
	logmkdir "${home}/.kodi" ${USER}
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

function mod3 {
	patch="--- orig.txt	2018-06-10 15:36:53.479009368 +0200
+++ mod.txt	2018-06-10 15:42:08.995666676 +0200
@@ -34,8 +34,9 @@
     // Beginning of modifier mappings.
     modifier_map Shift  { Shift_L, Shift_R };
     modifier_map Lock   { Caps_Lock };
-    modifier_map Control{ Control_L, Control_R };
+    modifier_map Control{ Control_L };
     modifier_map Mod2   { Num_Lock };
+    modifier_map Mod3   { Control_R };
     modifier_map Mod4   { Super_L, Super_R };
 
     // Fake keys for virtual<->real modifiers mapping:"
	echo "$patch">/tmp/symbols_pc.patch
	apply_patch /usr/share/X11/xkb/symbols/pc 2019c40a10ccb69d6b1d95c5762f8c3a09fce64b 63867d13946f00aa9017937ef0b4d3aad25caa52 /tmp/symbols_pc.patch
	gsettings_set_value org.gnome.desktop.wm.keybindings move-to-workspace-down "['<Shift><Mod3>Down']"
	gsettings_set_value org.gnome.desktop.wm.keybindings move-to-workspace-left "['<Shift><Mod3>Left']"
	gsettings_set_value org.gnome.desktop.wm.keybindings move-to-workspace-up "['<Shift><Mod3>Up']"
	gsettings_set_value org.gnome.desktop.wm.keybindings move-to-workspace-right "['<Shift><Mod3>Right']"

	gsettings_set_value org.gnome.desktop.wm.keybindings switch-to-workspace-down "['<Mod3>Down']"
	gsettings_set_value org.gnome.desktop.wm.keybindings switch-to-workspace-left "['<Mod3>Left']"
	gsettings_set_value org.gnome.desktop.wm.keybindings switch-to-workspace-up "['<Mod3>Up']"
	gsettings_set_value org.gnome.desktop.wm.keybindings switch-to-workspace-right "['<Mod3>Right']"
}

function zulip {
	logexec sudo apt-key adv --keyserver pool.sks-keyservers.net --recv 69AD12704E71A4803DCA3A682424BE5AE9BD10D9
	textfile /etc/apt/sources.list.d/zulip.list "deb https://dl.bintray.com/zulip/debian/ stable main"
	flag_need_apt_update=1
	install_apt_package zulip
	add_host zulip.statystyka.net 10.55.181.62
}

function owncloud {
	ver=$(get_ubuntu_version)
	if [[ "$ver" == "1604" ]]; then
		contents='deb http://download.opensuse.org/repositories/isv:/ownCloud:/desktop/Ubuntu_16.04/ /'
		add_apt_source_manual isv:ownCloud:desktop "$contents" https://download.opensuse.org/repositories/isv:ownCloud:desktop/Ubuntu_16.04/Release.key ownCloud_16.04_Release.key
	elif [[ "$ver" == "1804" ]]; then
		contents='deb http://download.owncloud.org/download/repositories/10.0/Ubuntu_18.04/ /'
		add_apt_source_manual isv:ownCloud:desktop "$contents" https://download.owncloud.org/download/repositories/10.0/Ubuntu_16.04/Release.key ownCloud_18.04_Release.key
	else
		errcho "Unsupported UBUNTU!!"
	fi
	install_apt_package owncloud-client
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

function gedit {
	if [ ! -f "~/.local/share/gedit/plugins/pair_char_completion.py" ]; then
		plik=$(get_cached_file gedit-pair-char-completion-1.0.6-gnome3.tar.gz https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/gedit-pair-char-autocomplete/gedit-pair-char-completion-1.0.6-gnome3.tar.gz)
		tmpdir=$(mktemp -d)
		uncompress_cached_file $plik $tmpdir
		pushd $tmpdir/gedit-pair-char-completion-1.0.6-gnome3
		logexec ${tmpdir}/gedit-pair-char-completion-1.0.6-gnome3/install.sh
		popd
		gsettings_add_to_array org.gnome.gedit.plugins active-plugins pair_char_completion
	fi
	
	if [ ! -f "~/.local/share/gedit/plugins/ex-mortis.plugin" ]; then
		plik=$(get_cached_file gedit-ex-mortis.tar.gz https://github.com/jefferyto/gedit-ex-mortis/archive/master.tar.gz)
		tmpdir=$(mktemp -d)
		uncompress_cached_file $plik $tmpdir
		logexec cp -R ${tmpdir}/gedit-ex-mortis-master/ex-mortis ~/.local/share/gedit/plugins
		logexec cp ${tmpdir}/gedit-ex-mortis-master/ex-mortis.plugin ~/.local/share/gedit/plugins
		gsettings_add_to_array org.gnome.gedit.plugins active-plugins ex-mortis
	fi
	
	if [ ! -d "/usr/share/gedit/plugins/crypto" ]; then
		plik=$(get_cached_file gedit-crypto.deb http://pietrobattiston.it/_media/gedit-crypto:gedit-crypto-plugin_0.5-1_all.deb)
		install_apt_package_file $plik gedit-crypto-plugin
		gsettings_add_to_array org.gnome.gedit.plugins active-plugins crypto
	fi
	
	if [ ! -f "~/.local/share/gedit/plugins/controlyourtabs.plugin" ]; then
		plik=$(get_cached_file gedit-control-your-tabs.tar.gz https://github.com/jefferyto/gedit-control-your-tabs/archive/master.tar.gz)
		tmpdir=$(mktemp -d)
		uncompress_cached_file $plik $tmpdir
		logexec cp -R ${tmpdir}/gedit-control-your-tabs-master/controlyourtabs ~/.local/share/gedit/plugins
		logexec cp ${tmpdir}/gedit-control-your-tabs-master/controlyourtabs.plugin ~/.local/share/gedit/plugins
		gsettings_add_to_array org.gnome.gedit.plugins active-plugins controlyourtabs
	fi
	install_apt_package gedit-plugins
	gsettings_add_to_array org.gnome.gedit.plugins active-plugins git
	gsettings_add_to_array org.gnome.gedit.plugins active-plugins textsize
	gsettings_add_to_array org.gnome.gedit.plugins active-plugins spell
	gsettings_add_to_array org.gnome.gedit.plugins active-plugins codecomment
	gsettings_add_to_array org.gnome.gedit.plugins active-plugins charmap
	gsettings_add_to_array org.gnome.gedit.plugins active-plugins charmap
	
	gsettings_set_value org.gnome.gedit.preferences.editor bracket-matching true
	gsettings_set_value org.gnome.gedit.preferences.editor highlight-current-line true
	gsettings_set_value org.gnome.gedit.preferences.editor background-pattern 'grid'
	gsettings_set_value org.gnome.gedit.preferences.editor display-line-numbers true
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

