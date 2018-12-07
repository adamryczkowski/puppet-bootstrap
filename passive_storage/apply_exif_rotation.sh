#!/bin/bash
#Rotates all JPGs according to their EXIF tag
#Checks for and installs if needed the exiftran tool

function install_apt_packages {
	local ans=0
	local to_install=""
	local packages="$@"
	for package in ${packages[@]}; do
		if ! dpkg -s "$package">/dev/null  2> /dev/null; then
			to_install="${to_install} ${package}"
		fi
	done
	if [[ "${to_install}" != "" ]]; then
		echo "I am going to install ${to_install}. You may be prompted for admin password."
		sudo apt update
		sudo apt-get --yes --force-yes -q  install $to_install
		return $?
	fi
	return 0
}
if [ ! -d "$1" ]; then
	if [ ! -f "$1" ]; then
		echo "Non existing $1"
		sleep 10
		exit 1
	fi
	install_apt_packages parallel exiftran
	parallel --jobs 2 --no-notice exiftran -a -i -p "{}" ::: "$@"
else
	cd "$1"
	install_apt_packages parallel exiftran
	find . -name "*[.jpg\|.jpeg\|.JPG\|.JPEG]" -and -not -type d | parallel --no-notice --jobs 2 exiftran -a -i -p "{}"
fi

echo "Done."
read -p "Press enter to continue"
