#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Prepares the machine for compilation of the IMGW PROPOZE code. It tries to load the essential packages via spack (if found),
otherwise it installs them from packages (requires root). 

TODO: Update packages as well


Usage:

$(basename $0) [--spack-location <path> [--force-spack] ] (--gcc6|--gcc7) 
               [--help] [--debug] [--log <output file>]


where
 --spack-location         - Location of Spack installation. Defaults to $HOME/tmp/spack
 --gcc6                   - Flag. If set, will prepare gcc6
 --gcc7                   - Flag. If set, will prepare gcc7
 --force-spack            - Flag. If set, installation will be done using spack.
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands


Example2:

$(basename $0) --docs --debug
"

home=$(get_home_dir)
spack_location=${home}/tmp/spack
use_gcc5=0
use_gcc6=0
use_gcc7=0
force_spack=0

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--spack-location)
	spack_location="$1"
	shift
	;;
	--gcc5)
	use_gcc5=1
	;;
	--gcc6)
	use_gcc6=1
	;;
	--gcc7)
	use_gcc7=1
	;;
	--force-spack)
	force_spack=1
	;;
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
	--docs)
	flag_docs=1
	;;
	-*)
	echo "Error: Unknown option: $1" >&2
	echo "$usage" >&2
	exit 1
	;;
esac
done

if [ -n "$debug" ]; then
	if [ -z "$log" ]; then
		log=/dev/stdout
	fi
	external_opts="--debug"
fi

if [ "$use_gcc5" == "0" ] && [ "$use_gcc6" == "0" ] && [ "$use_gcc7" == "0" ]; then
	errcho "Must specify at least on of --gcc6, --gcc6 or --gcc7. "
	echo "$usage"
	exit 1
fi

install_cmake=1
if which cmake>/dev/null; then
	install_cmake=0
fi

install_gcc5=1
if which gfortran-5>/dev/null && which gcc-5>/dev/null && which g++-5>/dev/null; then
	install_gcc5=0
fi

install_gcc6=1
if which gfortran-6>/dev/null && which gcc-6>/dev/null && which g++-6>/dev/null; then
	install_gcc6=0
fi

install_gcc7=1
if which gfortran-7>/dev/null && which gcc-7>/dev/null && which g++-7>/dev/null; then
	install_gcc7=0
fi

if [ -f "${spack_location}/share/spack/setup-env.sh" ]; then
	#First try using spack
	source "${spack_location}/share/spack/setup-env.sh"

	if ! spack find spack | grep "No package matches the query"; then
		install_cmake=0
	fi
	
	if ! spack find gcc@5 | grep "No package matches the query"; then
		install_gcc5=0
	fi
	if ! spack find gcc@6 | grep "No package matches the query"; then
		install_gcc6=0
	fi
	if ! spack find gcc@7 | grep "No package matches the query"; then
		install_gcc7=0
	fi
else
	if [ "$force_spack" == "1" ]; then
		errcho "Cannot force spack if spack is not loaded. Specify path to the spack with --spack-location <path>. (You can install it using prepare_spack.sh script)"
		echo "$usage"
		exit 1
	fi
fi



if [ "$install_cmake" == "1" ]; then
	if [ "$force_spack" == "1" ]; then
		spack install cmake
	else
		install_apt_package cmake
	fi
fi

if [ "$use_gcc5" == "1" ]; then
	if [ "$install_gcc5" == "1" ]; then
		if [ "$force_spack" == "1" ]; then
			spack install gcc@5.5.0
		else
#			ubuntu_code=$(get_ubuntu_codename)
#			if [ "$ubuntu_code" == "xenial" ]; then
#				add_ppa ubuntu-toolchain-r/test
#			fi
			install_apt_package gcc-5 g++-5 gfortran-5
		fi
	fi
fi

if [ "$use_gcc6" == "1" ]; then
	if [ "$install_gcc6" == "1" ]; then
		if [ "$force_spack" == "1" ]; then
			spack install gcc@6.4.0
		else
			ubuntu_code=$(get_ubuntu_codename)
			if [ "$ubuntu_code" == "xenial" ]; then
				add_ppa ubuntu-toolchain-r/test
			fi
			install_apt_package gcc-6 g++-6 gfortran-6
		fi
	fi
fi


if [ "$use_gcc7" == "1" ]; then
	if [ "$install_gcc7" == "1" ]; then
		if [ "$force_spack" == "1" ]; then
			spack install gcc@7.3.0
		else
			ubuntu_code=$(get_ubuntu_codename)
			if [ "$ubuntu_code" == "xenial" ]; then
				add_ppa ubuntu-toolchain-r/test
			fi
			install_apt_package gcc-7 g++-7 gfortran-7
		fi
	fi
fi
#install_apt_packages git cmake build-essential gfortran libboost-program-options-dev jq libboost-filesystem-dev libboost-system-dev libboost-log-dev libboost-date-time-dev libboost-thread-dev libboost-chrono-dev libboost-atomic-dev

#Adding github to known hosts
logexec ssh-keyscan -H github.com >> $home/.ssh/known_hosts

#Adding gitlab to known hosts:
logexec ssh-keyscan -H git1.imgw.pl >> $home/.ssh/known_hosts

