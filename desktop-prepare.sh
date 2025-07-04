#!/bin/bash
set -euo pipefail

## dependency: prepare_R-node.sh

cd "$(dirname "$0")"
. ./common.sh

usage="
Prepares an Ubuntu installation with common tweaks.

Usage:

$(basename "$0") [-r|--release <ubuntu release>] [--user <name of user>]
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
- i3wm
- kitty
- waterfox (=firefox)
- julia

--user <user name>       - Name of user. If specified, some extra user-specific tasks
will be performed for most of the tricks.
--repo-path              - Path to the repository. Some tweaks require it.
-r|--release             - Ubuntu release to be tweaked.
Currently supports only 16.04/xenial, so this option is meaningless.
--debug                  - Flag that sets debugging mode.
--log                    - Path to the log file that will log all meaningful commands


Example:

./$(basename "$0") --tweaks cli,nemo,smb,mod3,kodi,office2007,bumblebee,desktop,blender,laptop,zulip,owncloud,gedit,keepass,unity,firefox,i3wm,virtualbox,kitty,julia
"

dir_resolve() {
  cd "$1" 2>/dev/null || return $? # cd to desired directory; if fail, quell any error messages but return exit status
  pwd -P                           # output full, link-resolved path
}
mypath=${0%/*}
mypath=$(dir_resolve "$mypath")
cd "$mypath"

repo_path=/media/adam-minipc/other/debs
release=$(get_ubuntu_codename)
user=$USER
common_debug=0
tweaks=""
log=""

while [[ $# -gt 0 ]]; do
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
  -r | --release)
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

home=$(get_home_dir "${user}")

if [ -n "$common_debug" ]; then
  if [ -z "$log" ]; then
    log=/dev/stdout
  fi
fi

#Makes sure basic scripts are installed
function tweak_base {
  logmkdir /usr/local/lib/adam/scripts $user
  install_script files/discover_session_bus_address.sh /usr/local/lib/adam/scripts 0
  install_apt_packages git gdebi-core
  mount_dir "$repo_path" || true
}

function unity {
  if [ "$release" == "bionic" ]; then
    ext_path=$(get_cached_file "gnome_extensions/workspace-grid-for-3.16-to-3.26.zip" "https://github.com/zakkak/workspace-grid/releases/download/v1.4.1/workspace-grid-for-3.16-to-3.26.zip")
    install_gnome_extension "${ext_path}"

    gsettings_set_value org.gnome.shell.extensions.workspace-grid num-rows 3
    gsettings_set_value org.gnome.mutter dynamic-workspaces false
    gsettings_set_value org.gnome.shell.extensions.dash-to-dock dock-fixed false

    add_ppa unity7maintainers/unity7-desktop
    install_apt_package gnome-tweak-tool
  fi
  install_apt_package ubuntu-unity-desktop
}

function desktop {
  add_ppa yktooo/ppa
  install_apt_packages meld chromium-browser gparted indicator-sound-switcher
  gsettings_remove_from_array com.canonical.Unity.Launcher favorites 'application://org.gnome.Software.desktop'
  gsettings_remove_from_array com.canonical.Unity.Launcher favorites 'application://ubuntu-amazon-default.desktop'
  gsettings_set_value org.compiz.unityshell:/org/compiz/profiles/unity/plugins/unityshell/ launcher-hide-mode 1
  gsettings_set_value org.gnome.desktop.peripherals.touchpad scroll-method edge-scrolling
  gsettings_set_value org.gnome.desktop.screensaver lock-enabled false
  gsettings_set_value org.gnome.desktop.screensaver ubuntu-lock-on-suspend false
  gsettings_set_value com.canonical.Unity integrated-menus true
  gsettings_set_value org.gnome.desktop.input-sources show-all-sources true
  #	set_gsettings_array org.gnome.desktop.input-sources sources "[('xkb', 'pl+intl')]"
  gsettings set org.gnome.desktop.input-sources sources "[('xkb,', 'pl+intl')]"

  if [ "$release" == "bionic" ]; then
    install_apt_package gnome-tweak-tool
    ext_path=$(get_cached_file "gnome_extensions/workspace-grid-for-3.16-to-3.26.zip" "https://github.com/zakkak/workspace-grid/releases/download/v1.4.1/workspace-grid-for-3.16-to-3.26.zip")
    install_gnome_extension "${ext_path}"

    gsettings_set_value org.gnome.shell.extensions.workspace-grid num-rows 3
    gsettings_set_value org.gnome.mutter dynamic-workspaces false
    gsettings_set_value org.gnome.shell.extensions.dash-to-dock dock-fixed false
    gsettings_set_value org.compiz.unityshell:/org/compiz/profiles/unity/plugins/core/ hsize 3
    gsettings_set_value org.compiz.unityshell:/org/compiz/profiles/unity/plugins/core/ vsize 3

    add_ppa unity7maintainers/unity7-desktop
  fi

  if dpkg -s ubuntu-unity-desktop >/dev/null 2>/dev/null; then
    install_apt_packages unity tweak
  fi

  gsettings_set_value org.gnome.desktop.wm.preferences num-workspaces 9
  install_apt_package_file skypeforlinux-64.deb skypeforlinux "https://go.skype.com/skypeforlinux-64.deb"
  sudo apt-key export Skype | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/skype.gpg

  install_apt_packages redshift-gtk dconf-editor ibus-table-translit
  redshift-gtk &
}

function signal {
  #TODO
  sudo apt install curl
  curl -s https://updates.signal.org/desktop/apt/keys.asc | sudo apt-key add -
  echo "deb [arch=amd64] https://updates.signal.org/desktop/apt xenial main" | sudo tee -a /etc/apt/sources.list.d/signal-xenial.list
  sudo apt update && sudo apt install signal-desktop
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
  set -x
  echo "#TODO"
  logexec sudo dpkg --add-architecture i386
  release_key=$(get_cached_file WineHQ_Release.key https://dl.winehq.org/wine-builds/winehq.key)
  if [[ $(get_distribution) == "LinuxMint" ]]; then
    release=bionic
  else
    release=$(get_ubuntu_codename)
  fi

  logexec sudo apt-key add "${release_key}"
  add_apt_source_manual winehq "deb https://dl.winehq.org/wine-builds/ubuntu/ ${release} main" https://dl.winehq.org/wine-builds/winehq.key winehq.key

  #	release_key=$(get_cached_file PlayOnLinux_Release.key http://deb.playonlinux.com/public.gpg)
  #	logexec sudo apt-key add "${release_key}"

  #	add_apt_source_manual playonlinux "deb http://deb.playonlinux.com/ ${release} main" http://deb.playonlinux.com/public.gpg PlayOnLinux_Release.key
  if [[ $(get_ubuntu_codename) == bionic ]]; then
    install_apt_package_file libfaudio0_19.07-0~bionic_amd64.deb libfaudio:amd64 https://download.opensuse.org/repositories/Emulators:/Wine:/Debian/xUbuntu_18.04/amd64/libfaudio0_19.07-0~bionic_amd64.deb
    install_apt_package_file libfaudio0_19.07-0~bionic_i386.deb libfaudio:i386 https://download.opensuse.org/repositories/Emulators:/Wine:/Debian/xUbuntu_18.04/i386/libfaudio0_19.07-0~bionic_i386.deb
  fi

  do_update
  install_apt_packages winehq-staging #playonlinux gridsite-clients

  add_group wine_office
  add_usergroup "$user" wine_office
  local office_install="/opt/Office2007"
  uncompress_cached_file office2007_pl.tar.xz /opt ${user}:wine_office Office2007
  chown_dir ${office_install} "${user}:wine_office" wine_office
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

function laptop() {
install_pipx_command git+https://github.com/adamryczkowski/bright
install_file files/fix_permissions.sh /usr/local/lib/adam/scripts/ root 1
linetextfile /etc/pam.d/common-session "session optional    pam_exec.so /bin/sh /usr/local/lib/adam/scripts/fix_permissions.sh"

#	desktop
#	gsettings_set_value org.gnome.desktop.peripherals.touchpad click-method "fingers"
#	gsettings_set_value org.gnome.desktop.peripherals.touchpad edge-scrolling-enabled true
#	gsettings_set_value org.gnome.desktop.peripherals.touchpad two-finger-scrolling-enabled false
#	gsettings_set_value org.gnome.desktop.peripherals.touchpad scroll-method 'edge-scrolling'
#	gsettings_set_value org.gnome.desktop.peripherals.touchpad tap-to-click true
#	gsettings_set_value org.gnome.desktop.peripherals.touchpad natural-scroll false
#	install_apt_package_file xserver-xorg-input-synaptics
#	install_file files/30-touchpad.conf /etc/X11/xorg.conf.d root
#
#	install_script files/fix_permissions.sh /usr/local/lib/adam/scripts/fix_permissions.sh root
#	install_apt_packages python-is-python3
#	linetextfile /etc/pam.d/common-session "session optional pam_exec.so /bin/sh /usr/local/lib/adam/scripts/fix_permissions.sh"
#	install_file files/bright /usr/local/bin
#	install_file files/bright /usr/local/lib/adam/scripts

# udev rules for charging
install_file files/60-onbattery.rules /etc/udev/rules.d
install_file files/ac_changed.sh /usr/local/bin 1
install_apt_packages acpitool ubuntu-touch-sounds sox
crontab -l -u $USER >/tmp/cron_tmp.cron
linetextfile /tmp/cron_tmp.cron "* * * * * [ -f /tmp/discharging ] && play /usr/share/sounds/ubuntu/notifications/Blip.ogg"
sudo udevadm control --reload
crontab -u $USER /tmp/cron_tmp.cron
}

function nvidia() {
add_ppa graphics-drivers/ppa

release=$(get_ubuntu_version)

install_apt_package_file "cuda-repo-ubuntu${release}_9.1.85-1_amd64.deb" "cuda-repo-ubuntu${release}" http://developer.download.nvidia.com/compute/cuda/repos/ubuntu${release}/x86_64/cuda-repo-ubuntu${release}_9.1.85-1_amd64.deb
if [ "$?" == "0" ]; then
	logexec sudo apt-key adv --fetch-keys http://developer.download.nvidia.com/compute/cuda/repos/ubuntu${release}/x86_64/7fa2af80.pub
fi

do_update
install_apt_packages ubuntu-drivers-common
logexec sudo ubuntu-drivers autoinstall
nvidia_package=$(apt list --installed | grep -E 'nvidia-[0-9]+/')
pattern='nvidia-([0-9]+)/'
if [[ "${nvidia_package}" =~ $pattern ]]; then
	nvidia_version=${BASH_REMATCH[1]}
else
	errcho "Unexpected error"
	exit 1
fi
}

function cuda() {
install_apt_package_file "cuda-repo-ubuntu${release}_9.1.85-1_amd64.deb" "cuda-repo-ubuntu${release}" http://developer.download.nvidia.com/compute/cuda/repos/ubuntu${release}/x86_64/cuda-repo-ubuntu${release}_9.1.85-1_amd64.deb
if [ "$?" == "0" ]; then
	logexec sudo apt-key adv --fetch-keys "http://developer.download.nvidia.com/compute/cuda/repos/ubuntu$(get_ubuntu_version)/x86_64/7fa2af80.pub"
fi
install_apt_package cuda

}

function bumblebee() {
#	return 1 #not ready
#  see: https://askubuntu.com/questions/1029169/bumblebee-doesnt-work-on-ubuntu-18-04/1042950#1042950
add_ppa graphics-drivers/ppa
add_ppa bumblebee/testing

do_update

linetextfile /etc/environment "__GLVND_DISALLOW_PATCHING=1"

#	textfile /etc/modprobe.d/blacklist-nvidia.conf "/etc/modprobe.d/blacklist-nvidia.conf
#/etc/modprobe.d/blacklist-nvidia.conf" root

#	sudo systemctl disable nvidia-persistenced
#	sudo systemctl disable nvidia-fallback.service

install_apt_package ubuntu-drivers-common ubuntu-drivers
logexec sudo ubuntu-drivers autoinstall
nvidia_package=$(apt list --installed | grep -E 'nvidia-[0-9]+/')
pattern='nvidia-([0-9]+)/'
if [[ "${nvidia_package}" =~ $pattern ]]; then
	# shellcheck disable=SC2034
	nvidia_version=${BASH_REMATCH[1]}
else
	errcho "Unexpected error"
	exit 1
fi
install_apt_packages bumblebee bumblebee-nvidia tlp powertop nvidia-prime
install_file files/bumblebee.conf /etc/bumblebee/bumblebee.conf root
logexec sudo prime-select intel
#TODO: https://gist.github.com/whizzzkid/37c0d365f1c7aa555885d102ec61c048
}

function cli() {
#TODO: remove entirely, in favour of prepare_ubuntu.sh
tweak_base
install_apt_packages git htop liquidprompt nethogs iftop iotop mc byobu openssh-server software-properties-common curl dtrx
logexec liquidprompt_activate
logexec sudo liquidprompt_activate
home=$(get_home_dir)
logmkdir ${home}/tmp
get_git_repo https://github.com/adamryczkowski/update-all ${home}/tmp

install_file files/snap /usr/local/bin/snap root
set_executable /usr/local/bin/snap
#youtube-dl
}

function rdesktop() {
reposerver="$(dirname ${repo_path})/r-mirror"
$mypath/prepare-R-node.sh --rstudio --repo-server file://${reposerver} --deb-folder ${repo_path} --debug
}

function virtualbox() {
#	release_key=$(get_cached_file Oracle_2016_Release.key https://www.virtualbox.org/download/oracle_vbox_2016.asc)
#	cat "${release_key}" | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/virtualbox.gpg
#	logexec sudo apt-key add "${release_key}"
#	release_key=$(get_cached_file Oracle_Release.key https://www.virtualbox.org/download/oracle_vbox.asc)
#	logexec sudo apt-key add "${release_key}"
add_apt_source_manual virtualbox "deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/virtualbox.gpg] https://download.virtualbox.org/virtualbox/debian jammy contrib" https://www.virtualbox.org/download/oracle_vbox_2016.asc
add_ppa thebernmeister/ppa
install_apt_packages virtualbox-6.1 indicator-virtual-box
if ! sudo VBoxManage list extpacks | grep -q -F "Oracle VM VirtualBox Extension Pack"; then
	version=$(VBoxManage -v)
	pattern='^([0-9\.]+)r.*'
	if [[ $version =~ $pattern ]]; then
		version=${BASH_REMATCH[1]}
		vb_ext_filename="Oracle_VM_VirtualBox_Extension_Pack-${version}.vbox-extpack"
		vb_ext_path=$(get_cached_file ${vb_ext_filename} https://download.virtualbox.org/virtualbox/${version}/${vb_ext_filename})
		echo "y" | sudo VBoxManage extpack install ${vb_ext_path} --replace
	fi
fi
homedir=$(get_home_dir)
if [ ! -f "${homedir}/.config/autostart/indicator-virtual-box.py.desktop" ]; then
	logexec cp /usr/share/applications/indicator-virtual-box.py.desktop "${homedir}/.config/autostart/indicator-virtual-box.py.desktop"
fi
logexec sudo update-secureboot-policy --new-key
}

function kodi() {
add_ppa team-xbmc/ppa
install_apt_package kodi
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
# shellcheck disable=SC1078
textfile "${home}/.kodi/userdata/passwords.xml" "\
	<passwords>
<path>
<from pathversion=\"1\">smb://szesciodysk/filmy</from>
<to pathversion=\"1\">smb://adam:Zero%20tolerancji@szesciodysk/filmy/</to>
</path>
</passwords>"
}

function nemo() {
#	add_ppa webupd8team/nemo3
do_update
install_apt_package nemo nemo

gsettings_set_value org.gnome.desktop.background show-desktop-icons false
xdg-mime default nemo.desktop inode/directory application/x-gnome-saved-search
gsettings_remove_from_array com.canonical.Unity.Launcher favorites 'application://org.gnome.Nautilus.desktop'
gsettings_add_to_array com.canonical.Unity.Launcher favorites 'application://nemo.desktop' 1
gsettings_set_value org.nemo.preferences show-open-in-terminal-toolbar true
gsettings_set_value org.nemo.preferences default-folder-viewer "compact-view"
gsettings_set_value org.nemo.preferences show-hidden-files true

logmkdir "${home}/.local/bin" ${user}
cp_file "$(get_cached_file apply_exif_rotation.sh https://raw.githubusercontent.com/adamryczkowski/puppet-bootstrap/master/passive_storage/apply_exif_rotation.sh)" "${home}/.local/bin" "${user}"
set_executable "${home}/.local/bin/apply_exif_rotation.sh"
cp_file "$(get_cached_file fix_jpeg_rotation_dir.nemo_action https://raw.githubusercontent.com/adamryczkowski/puppet-bootstrap/master/passive_storage/fix_jpeg_rotation_dir.nemo_action)" "${home}/.local/share/nemo/actions" "${user}"
cp_file "$(get_cached_file fix_jpeg_rotation_files.nemo_action https://raw.githubusercontent.com/adamryczkowski/puppet-bootstrap/master/passive_storage/fix_jpeg_rotation_files.nemo_action)" "${home}/.local/share/nemo/actions" "${user}"
}

function mod3() {
set -x
patch="--- /usr/share/X11/xkb/symbols/pc	2024-02-05 02:24:20.000000000 +0100
+++ pc	2025-05-24 12:38:16.221637893 +0200
@@ -28,7 +28,8 @@

modifier_map Shift   { Shift_L, Shift_R };
modifier_map Lock    { Caps_Lock };
-    modifier_map Control { Control_L, Control_R };
+    modifier_map Control { Control_L };
+    modifier_map Mod3    { Control_R };
modifier_map Mod1    { Alt_L, Alt_R, Meta_L, Meta_R };
modifier_map Mod2    { Num_Lock };
modifier_map Mod4    { Super_L, Super_R };"
echo "$patch" >/tmp/symbols_pc.patch

#	apply_patch /usr/share/X11/xkb/symbols/pc 2019c40a10ccb69d6b1d95c5762f8c3a09fce64b 63867d13946f00aa9017937ef0b4d3aad25caa52 /tmp/symbols_pc.patch
apply_patch /usr/share/X11/xkb/symbols/pc c8231d3a67cdf7656f7a141dc38f36a0cb241e5e a4fa42917d882f8492162c045833619d3d2d2cb2 /tmp/symbols_pc.patch
if [ "$(get_distribution)" == "LinuxMint" ]; then
	gsettings_set_value org.cinnamon.desktop.wm.keybindings move-to-workspace-down "['<Shift><Mod3>Down']"
	gsettings_set_value org.cinnamon.desktop.wm.keybindings move-to-workspace-left "['<Shift><Mod3>Left']"
	gsettings_set_value org.cinnamon.desktop.wm.keybindings move-to-workspace-up "['<Shift><Mod3>Up']"
	gsettings_set_value org.cinnamon.desktop.wm.keybindings move-to-workspace-right "['<Shift><Mod3>Right']"

	gsettings_set_value org.cinnamon.desktop.wm.keybindings switch-to-workspace-down "['<Mod3>Down']"
	gsettings_set_value org.cinnamon.desktop.wm.keybindings switch-to-workspace-left "['<Mod3>Left']"
	gsettings_set_value org.cinnamon.desktop.wm.keybindings switch-to-workspace-up "['<Mod3>Up']"
	gsettings_set_value org.cinnamon.desktop.wm.keybindings switch-to-workspace-right "['<Mod3>Right']"
elif [ "$(get_distribution)" == "Ubuntu" ]; then
	gsettings_set_value org.gnome.desktop.wm.keybindings move-to-workspace-down "['<Shift><Mod3>Down']"
	gsettings_set_value org.gnome.desktop.wm.keybindings move-to-workspace-left "['<Shift><Mod3>Left']"
	gsettings_set_value org.gnome.desktop.wm.keybindings move-to-workspace-up "['<Shift><Mod3>Up']"
	gsettings_set_value org.gnome.desktop.wm.keybindings move-to-workspace-right "['<Shift><Mod3>Right']"

	gsettings_set_value org.gnome.desktop.wm.keybindings switch-to-workspace-down "['<Mod3>Down']"
	gsettings_set_value org.gnome.desktop.wm.keybindings switch-to-workspace-left "['<Mod3>Left']"
	gsettings_set_value org.gnome.desktop.wm.keybindings switch-to-workspace-up "['<Mod3>Up']"
	gsettings_set_value org.gnome.desktop.wm.keybindings switch-to-workspace-right "['<Mod3>Right']"
fi
}

function waterfox() {
add_apt_source_manual waterfox "deb http://download.opensuse.org/repositories/home:/hawkeye116477:/waterfox/xUbuntu_$(get_ubuntu_version .)/ /" "https://download.opensuse.org/repositories/home:hawkeye116477:waterfox/xUbuntu_$(get_ubuntu_version .)/Release.key" waterfox.key
install_apt_package waterfox

#TODO: Install addon: https://github.com/iamadamdev/bypass-paywalls-firefox

#	waterfox_version=$(get_latest_github_release_name MrAlex94/Waterfox)
#	pattern='^([0-9\.]+)\-(classic[0-9\-]+)$'
#	pattern='^([0-9\.]+)\-.*$'
#	if [[ "${waterfox_version}" =~ $pattern ]]; then
#	   ver_str="${BASH_REMATCH[1]}"
#	   clas_str="${BASH_REMATCH[2]}"
#   else
#      return 1
#   fi
#	link="https://storage-waterfox.netdna-ssl.com/releases/linux64/installer/waterfox-classic-${ver_str}.en-US.linux-x86_64.tar.bz2"
#	filename="waterfox-${ver_str}.en-US.linux-x86_64.tar.bz2"
#	file=$(get_cached_file "$filename" "$link")
#
#	uncompress_cached_file ${filename} "/opt/waterfox"
#
#	chown_dir "/opt/waterfox" root root

#	install_script ${DIR}/files/waterfox.desktop /usr/share/applications/waterfox.desktop
#
#	make_symlink /opt/waterfox/waterfox /usr/local/bin/waterfox
}

function firefox() {
install_apt_package firefox
#TODO: Install scrapbook with python -m pip install -U webscrapbook
#Then make a user systemd script on ~/.local/share/systemd/user/scrapbook.service with contents:
#[Unit]
#Description=WebScrapbook serve component
#
#[Service]
#WorkingDirectory=/home/Adama-docs/Adam/Scrapbook
#RemainAfterExit=true
#ExecStart=/home/adam/.local/bin/wsb serve
#
#[Install]
#WantedBy=default.target
#
#
# enable the script with systemctl --user enable scrapbook
# and then run it with systemctl --user start scrapbook
#
# To convert from the old scrapbook X with wsb convert sb2wsb /path/to/webscrapbook /path/to/scrapbookX

}

function zulip() {
logexec sudo apt-key adv --keyserver pool.sks-keyservers.net --recv 69AD12704E71A4803DCA3A682424BE5AE9BD10D9
textfile /etc/apt/sources.list.d/zulip.list "deb https://dl.bintray.com/zulip/debian/ stable main"
# shellcheck disable=SC2034
flag_need_apt_update=1
install_apt_package zulip
add_host zulip.statystyka.net 10.55.181.62
}

function owncloud() {
ver=$(get_ubuntu_version)
if [[ "$ver" == "1604" ]]; then
	release_key=$(get_cached_file owncloud_1604_Release.key https://download.owncloud.org/download/repositories/production/Ubuntu_16.04/Release.key)
	logexec sudo apt-key add "${release_key}"
	contents='deb http://download.opensuse.org/repositories/isv:/ownCloud:/desktop/Ubuntu_16.04/ /'
	#		add_apt_source_manual isv:ownCloud:desktop "$contents" https://download.opensuse.org/repositories/isv:ownCloud:desktop/Ubuntu_16.04/Release.key ownCloud_16.04_Release.key
elif [[ "$ver" == "1804" ]]; then
	release_key=$(get_cached_file owncloud_1804_Release.key https://download.owncloud.org/download/repositories/production/Ubuntu_18.04/Release.key)
	logexec sudo apt-key add "${release_key}"

	contents='deb http://download.owncloud.org/download/repositories/10.0/Ubuntu_18.04/ /'
	add_apt_source_manual isv:ownCloud:desktop "$contents" https://download.owncloud.org/download/repositories/10.0/Ubuntu_16.04/Release.key ownCloud_18.04_Release.key
else
	errcho "Unsupported UBUNTU!!"
fi
install_apt_packages owncloud-client libgnome-keyring0 python-keyring gnome-keyring
}

function smb() {
install_apt_package cifs-utils
textfile /etc/samba/user "username=adam
password=Zero tolerancji" $user

declare -a folders=("szesciodysk/filmy" "szesciodysk/niezbednik" "szesciodysk/docs" "szesciodysk/adam" "szesciodysk/zdjecia")
declare -a shares=("filmy" "niezbednik" "docs" "adam" "zdjecia")
host=szesciodysk
add_host $host 192.168.10.6 ${host}.dom.statystyka.net

local i=1
arraylength=${#folders[@]}
for ((i = 1; i < ${arraylength} + 1; i++)); do
	folder=/media/${folders[$i - 1]}
	share=${shares[$i - 1]}
	logmkdir ${folder}
	smb_share_client ${host} ${share} ${folder} /etc/samba/user
	foldername=$(basename ${folder})
#	gsettings_add_to_array com.canonical.Unity.Devices blacklist ${foldername}
done

declare -a folders=("adam-minipc/download" "adam-minipc/other" "adam-minipc/unfinished" "adam-minipc/videos")
declare -a shares=("download" "other" "partial" "videos")
host=adam-minipc
add_host $host 192.168.10.2 ${host}.dom.statystyka.net

local i=1
arraylength=${#folders[@]}
for ((i = 1; i < ${arraylength} + 1; i++)); do
	folder=/media/${folders[$i - 1]}
	share=${shares[$i - 1]}
	logmkdir ${folder}
	smb_share_client ${host} ${share} ${folder} /etc/samba/user
	foldername=$(basename ${folder})
#	gsettings_add_to_array com.canonical.Unity.Devices blacklist ${foldername}
done
}

function gedit() {
set -x
install_apt_packages jq
localhome=$(get_home_dir $user)
logmkdir /opt/gedit-plugins

if [ ! -f "${localhome}/.local/share/gedit/plugins/pair_char_completion.py" ]; then
	plik=$(get_cached_file gedit-pair-char-completion-1.0.6-gnome3.tar.gz https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/gedit-pair-char-autocomplete/gedit-pair-char-completion-1.0.6-gnome3.tar.gz)
	tmpdir=$(mktemp -d)

	uncompress_cached_file $plik $tmpdir $user pair_char_completion
	pushd $tmpdir/pair_char_completion
	logexec ${tmpdir}/pair_char_completion/install.sh
	popd
fi
gsettings_add_to_array org.gnome.gedit.plugins active-plugins pair_char_completion

if [ ! -f "${localhome}/.local/share/gedit/plugins/ex-mortis.plugin" ]; then
	install_gh_source jefferyto/gedit-ex-mortis /opt/gedit-plugins "" ex-mortis

	#		plik=$(get_cached_file gedit-ex-mortis.tar.gz https://github.com/jefferyto/gedit-ex-mortis/archive/master.tar.gz)
	#		tmpdir=$(mktemp -d)
	#		uncompress_cached_file $plik $tmpdir $user ex-mortis
	logexec cp -R /opt/gedit-plugins/ex-mortis/ex-mortis ${localhome}/.local/share/gedit/plugins
	logexec cp /opt/gedit-plugins/ex-mortis/ex-mortis.plugin ${localhome}/.local/share/gedit/plugins
fi
gsettings_add_to_array org.gnome.gedit.plugins active-plugins ex-mortis

if [ ! -d "/usr/share/gedit/plugins/crypto" ]; then
	plik=$(get_cached_file gedit-crypto.deb http://pietrobattiston.it/_media/gedit-crypto:gedit-crypto-plugin_0.5-1_all.deb)
	install_apt_package_file "$plik" gedit-crypto-plugin
	gsettings_add_to_array org.gnome.gedit.plugins active-plugins crypto
fi
gsettings_add_to_array org.gnome.gedit.plugins active-plugins crypto

if [ ! -f "${localhome}/.local/share/gedit/plugins/controlyourtabs.plugin" ]; then
	install_gh_source jefferyto/gedit-control-your-tabs /opt/gedit-plugins "" control-your-tabs

	logexec cp -R /opt/gedit-plugins/control-your-tabs/controlyourtabs ${localhome}/.local/share/gedit/plugins
	logexec cp $/opt/gedit-plugins/control-your-tabs/controlyourtabs.plugin ${localhome}/.local/share/gedit/plugins
fi
gsettings_add_to_array org.gnome.gedit.plugins active-plugins controlyourtabs
install_apt_packages gedit-plugins gedit-plugin-text-size
gsettings_add_to_array org.gnome.gedit.plugins active-plugins git
gsettings_add_to_array org.gnome.gedit.plugins active-plugins textsize
gsettings_add_to_array org.gnome.gedit.plugins active-plugins spell
gsettings_add_to_array org.gnome.gedit.plugins active-plugins codecomment
gsettings_add_to_array org.gnome.gedit.plugins active-plugins charmap

gsettings_set_value org.gnome.gedit.preferences.editor bracket-matching true
gsettings_set_value org.gnome.gedit.preferences.editor highlight-current-line true
gsettings_set_value org.gnome.gedit.preferences.editor background-pattern 'grid'
gsettings_set_value org.gnome.gedit.preferences.editor display-line-numbers true
gsettings_set_value org.gnome.gedit.preferences.editor tabs-size 3
gsettings_set_value org.gnome.gedit.preferences.editor auto-indent true

logmkdir "${localhome}/.local/share/gedit/styles"
dracula=$(get_cached_file dracula.xml https://raw.githubusercontent.com/dracula/gedit/master/dracula.xml)
install_file "$dracula" "${localhome}/.local/share/gedit/styles/dracula.xml" $user
gsettings_set_value org.gnome.gedit.preferences.editor scheme 'oblivion'

}

function keepass() {
add_ppa jtaylor/keepass
install_apt_package keepass2 xdotool libmono-system-configuration-install4.0-cil libmono-system-management4.0-cil libmono-csharp4.0c-cil libmono-microsoft-csharp4.0-cil mono-mcs
file=$(get_latest_github_release kee-org/keepassrpc KeePassRPC.plgx)
echo "file=$file"
cp_file "$file" /usr/lib/keepass2/plugins/KeePassRPC.plgx root
}

function julia() {
set -x
local julia_version
local julia_path
julia_version=$(get_latest_github_release_name JuliaLang/julia skip_v)
local pattern='^([0-9]+\.[0-9])\..*'
if [[ $julia_version =~ $pattern ]]; then
	local short_version=${BASH_REMATCH[1]}
else
	echo "Wrong format of version: ${julia_version}"
	return 1
fi
local julia_file="julia-${julia_version}-linux-x86_64.tar.gz"
local julia_link="https://julialang-s3.julialang.org/bin/linux/x64/${short_version}/${julia_file}"
julia_path="$(get_cached_file "${julia_file}" "${julia_link}")"
uncompress_cached_file "${julia_path}" /opt/julia $user

make_symlink /opt/julia/bin/julia /usr/local/bin/julia

install_apt_packages hdf5-tools #for HDF5 Julia package
install_atom_packages uber-juno

$(which julia) -e 'using Pkg;Pkg.add(["Revise", "IJulia", "Rebugger", "RCall", "Knet", "Plots", "StatsPlots" , "DataFrames", "JLD", "Flux", "Debugger", "Weave"]);ENV["PYTHON"]=""; Pkg.build(); using Revise; using IJulia; using Rebugger; using RCall; using Knet; using Plots; using StatsPlots; using DataFrames; using JLD; using Flux; using Debugger'
}

function i3wm() {
tweaks+="fix_backlight_permissions"

#	install_apt_package_file keyring.deb sur5r-keyring https://debian.sur5r.net/i3/pool/main/s/sur5r-keyring/sur5r-keyring_2023.02.18_all.deb
#	add_apt_source_manual sur5r-i3 "deb [arch=amd64] http://debian.sur5r.net/i3/ $(get_ubuntu_codename) universe"

#	/etc/apt/sources.list.d/sur5r-i3.list
install_apt_packages i3 alsa-utils pasystray apparmor-notify lxappearance scrot gnome-screenshot compton fonts-firacode suckless-tools terminator sysstat lxappearance gtk-chtheme acpi pulseaudio-utils
#   install_apt_packages qt4-qtconfig

install_pipx_command "git+https://github.com/adamryczkowski/bright"

get_git_repo https://github.com/vivien/i3blocks "${home}/tmp"
if ! which i3blocks >/dev/null; then
	install_apt_packages autoconf automake build-essential
	pushd "${home}/tmp/i3blocks"
	logexec ./autogen.sh
	logexec ./configure
	logexec make
	logexec sudo make install
	popd
fi
logmkdir "${home}/.config"

get_git_repo https://gitlab.com/adamwam/i3-config.git "${home}/.config"
get_git_repo https://gitlab.com/adamwam/i3blocks-config.git "${home}/.config"
make_symlink "${home}/.config/i3-config/i3" "${home}/.config/i3"
make_symlink "${home}/.config/i3-config/terminator" "${home}/.config/terminator"
make_symlink "${home}/.config/i3blocks-config" "${home}/.config/i3blocks"
make_symlink "${home}/.config/i3-config/albert" "${home}/.config/albert"
make_symlink "${home}/.config/i3-config/fusuma" "${home}/.config/fusuma"
logexec sudo gem install fusuma
logexec sudo usermod -aG input "${user}"

add_apt_source_manual manuelschneid3r "deb http://download.opensuse.org/repositories/home:/manuelschneid3r/xUbuntu_$(get_ubuntu_version .)/ /" "https://download.opensuse.org/repositories/home:manuelschneid3r/xUbuntu_$(get_ubuntu_version .)/Release.key" manuelschneid3r.key
install_script files/i3exit '/usr/local/bin' root

install_apt_packages pcmanfm units playerctl # albert

#	install_apt_package_file libplayerctl2_2.0.1-1_amd64.deb libplayerctl2 http://ftp.nl.debian.org/debian/pool/main/p/playerctl/libplayerctl2_2.0.1-1_amd64.deb
#	install_apt_package_file playerctl_2.0.1-1_amd64.deb playerctl http://ftp.nl.debian.org/debian/pool/main/p/playerctl/playerctl_2.0.1-1_amd64.deb

input_class_contents=$(
	cat <<EOF
Section "InputClass"
    Identifier "libinput touchpad catchall"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "Tapping" "on"
    Option "TappingButtonMap" "lrm"
    Option "NaturalScrolling" "off"
    Option "DisableWhileTyping" "0"
EndSection
EOF
)
textfile "/etc/X11/xorg.conf.d/40-libinput.conf" "${input_class_contents}" root

#Dark theme
install_apt_packages gnome-themes-extra
if [ ! -f "${home}/.config/gtk-3.0/settings.ini" ]; then
	logmkdir "${home}/.config/gtk-3.0"
	textfile "${home}/.config/gtk-3.0/settings.ini" "[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=hicolor
gtk-font-name=Sans 10
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=0
gtk-toolbar-style=GTK_TOOLBAR_BOTH
gtk-toolbar-icon-size=GTK_ICON_SIZE_LARGE_TOOLBAR
gtk-button-images=1
gtk-menu-images=1
gtk-enable-event-sounds=1
gtk-enable-input-feedback-sounds=1
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintfull
	" "${user}"
else
	linetextfile "${home}/.config/gtk-3.0/settings.ini" "gtk-application-prefer-dark-theme=1"
	linetextfile "${home}/.config/gtk-3.0/settings.ini" "gtk-theme-name=Adwaita-dark"
fi

#https://i3wm.org/docs/repositories.html
#https://askubuntu.com/questions/1080671/how-can-i-install-playerctl
#https://github.com/unix121/i3wm-themer

#	if ! which polybar >/dev/null; then
#		install_apt_packages cmake cmake-data libcairo2-dev libxcb1-dev libxcb-ewmh-dev libxcb-icccm4-dev libxcb-image0-dev libxcb-randr0-dev libxcb-util0-dev libxcb-xkb-dev pkg-config python-xcbgen xcb-proto libxcb-xrm-dev i3-wm libasound2-dev libmpdclient-dev libiw-dev libcurl4-openssl-dev libpulse-dev libxcb-composite0-dev xcb libxcb-ewmh2 rofi
#		get_git_repo https://github.com/jaagr/polybar.git /tmp/polybar polybar
#		pushd /tmp/polybar
#		./build.sh --all-features --auto
#	fi

install_apt_packages fonts-noto fonts-hack fonts-font-awesome fonts-powerline

install_apt_packages libinput-tools ruby

#	get_git_repo https://github.com/flumm/Themes.git ${home}/tmp/i3themes i3themes
}

function kitty() {
local version
local kitty_source
version=$(get_latest_github_release_name kovidgoyal/kitty skip_v)
local file="kitty-${version}-x86_64.txz"
# shellcheck disable=SC2034
kitty_source=$(get_latest_github_release kovidgoyal/kitty "${file}" "${file}")
uncompress_cached_file "$file" /opt/kitty $user

make_symlink /opt/kitty/bin/kitty /usr/local/bin/kitty
if which nemo >/dev/null; then
	gsettings set_value org.cinnamon.desktop.default-applications.terminal exec "kitty"
fi

logexec sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /opt/kitty/bin/kitty 100
linetextfile ${home}/.bashrc 'alias ssh="kitty +kitten ssh"'

# libcairo-script-interpreter2 libfontconfig1-dev libfreetype6-dev libiw30 libmpdclient2 libpixman-1-dev
# libxcb-composite0 libxcb-render0-dev libxcb-shape0-dev libxcb-shm0-dev libxcb-util-dev
#libxcb-xfixes0-dev libxext-dev libxrender-dev x11proto-xext-dev
}

function fix_backlight_permissions() {
install_script files/fix_permissions.sh '/usr/local/lib/adam/scripts' root 1
linetextfile /etc/pam.d/common-session "session optional pam_exec.so /bin/sh /usr/local/lib/adam/scripts/fix_permissions.sh"
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
