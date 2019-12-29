#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Prepares spack repository. Does not require root priviledges if git is present.


Usage:

$(basename $0) [--user <username>]  [--spack-location <spack_path>] [--spack-mirror <spack_mirror>] [--pre-install <spack_package_name1>] [--pre-install <spack_package_name2>]...
                [--help] [--debug] [--log <output file>] 


where
 --user                       - Username to install the spack to. Defaults to the current user.
 --spack-location             - Name of the directory to install spack into. Defaults to ~/tmp/spack
 --spack_mirror               - Location of local spack mirror
 --pre-install                - Name of the spack packages that will be installed in sequence
 --debug                      - Flag that sets debugging mode. 
 --log                        - Path to the log file that will log all meaningful commands

Example2:

$(basename $0) --debug --spack-mirror /media/adam-minipc/other/spack-mirror

"


if [ -z "$1" ]; then
	echo "$usage" >&2
	exit 0
fi

set -x

spack_location="auto"
spack_mirror=""
pre_install=()
user="$USER"

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
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
	--user)
	user="$1"
	shift
	;;
	--spack-location)
	spack_location="$1"
	shift
	;;
	--spack-mirror)
	spack_mirror="$1"
	shift
	;;
	--pre-install)
	pre_install+=("$1")
	shift
	;;
	-*)
	echo "Error: Unknown option: $1" >&2
	echo "$usage" >&2
	exit 1
	;;
esac
done

install_apt_packages git python

#. Install spack
need_bootstrap=0

if [[ "${spack_location}" == "auto" ]]; then
   spack_location=$(get_home_dir ${user})/tmp/spack
fi

if [ ! -d "${spack_location}/.git" ]; then
	base_location=$(dirname ${spack_location})
	if [ ! -d "${base_location}" ]; then
	   logmkdir $base_location $user
	fi
	logexec sudo -u ${user} git clone --depth 1 https://github.com/spack/spack ${spack_location}
	need_bootstrap=1
else
   logexec pushd "${spack_location}"
   logexec sudo -u ${user} git pull
   logexec popd
fi

tmpscript=$(mktemp --suffix=.sh)
echo "#!/bin/bash" > ${tmpscript}
echo "source \"${spack_location}/share/spack/setup-env.sh\"" >> ${tmpscript}
source "${spack_location}/share/spack/setup-env.sh"

if [ "$spack_mirror" != "" ]; then
	if ! spack mirror list | grep ${spack_mirror} >/dev/null; then
		if spack mirror list | grep "^custom_mirror " >/dev/null; then
			echo "spack mirror remove custom_mirror" >> ${tmpscript}
		fi
		pattern='^file:/(/.*)$'
		if [[ $spack_mirror =~ $pattern ]]; then
			spack_mirror="${BASH_REMATCH[1]}"
		fi
		echo "spack mirror add custom_mirror file://${spack_mirror}" >> ${tmpscript}
	fi
fi

if [ "$need_bootstrap" == "1" ]; then
	echo "spack bootstrap" >> ${tmpscript}
	echo "source \"${spack_location}/share/spack/setup-env.sh\"" >> ${tmpscript}
fi

for spack_mod in ${pre_install[*]}; do
	echo "spack install ${spack_mod}" >> ${tmpscript}
done

sudo bash -u ${user} -x ${tmpscript}
