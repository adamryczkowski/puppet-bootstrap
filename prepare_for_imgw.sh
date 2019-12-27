#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Prepares the machine for compilation of the IMGW PROPOZE code. It tries to load the essential packages via spack (if found),
otherwise it installs them from packages (requires root). 

TODO: Update packages as well


Usage:

$(basename $0) [--spack-location <path> [--force-spack] ] --gcc <number>
               [--help] [--debug] [--log <output file>]


where
 --spack-location         - Location of Spack installation. Defaults to $HOME/tmp/spack or /opt/spack (first found)
                            If spack is found, the script assumes its packages will be used. New packages
                            will be installed on spack only if --force-spack. 
                            Script does not install spack.
 --gcc <version>          - Flag. If set, will prepare gcc in the specified version. 
                            Valid numbers: 5, 6, 7, 8 and 9.
 --force-spack            - Flag. If set, installation will be done using spack.
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands


Example2:

$(basename $0) --docs --debug
"

home=$(get_home_dir ${USER})
spack_location=auto
use_gcc=""
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
	--gcc)
   if [ "$use_gcc" != "5" ] && [ "$use_gcc" != "6" ] && [ "$use_gcc" != "7" ] && [ "$use_gcc" != "8" ] && [ "$use_gcc" != "9" ]; then
	   errcho "Must specify --gcc <N> with version number N 5, 6, 7, 8 or 9"
	   echo "$usage"
	   exit 1
   fi
   gccver="$1"
	install_gcc${gccver}=1
	shift
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

if [[ "$spack_location" == "auto" ]]; then
   if [ -f ${home}/tmp/spack/share/spack/setup-env.sh ]; then
      spack_location=${home}/tmp/spack
   elif [ -f /opt/spack/share/spack/setup-env.sh ]; then
      spack_location=/opt/spack
   else
      spack_location=""
   fi
fi

if [ -n "$debug" ]; then
	if [ -z "$log" ]; then
		log=/dev/stdout
	fi
	external_opts="--debug"
fi


install_cmake=1
if which cmake>/dev/null; then
	install_cmake=0
fi


if [ -f "${spack_location}/share/spack/setup-env.sh" ]; then
   has_spack=1
   source "${spack_location}/share/spack/setup-env.sh"
else
   has_spack=0
fi

if [[ "$force_spack" ]]; then
   if ! [[ "$has_spack" ]]; then
      errcho "Cannot find spack in ${spack_location}. Install spack first."
      return -1
   fi
fi

for i in {5..9}; do
   if [[ "${install_gcc${i}}" == 1 ]]; then
      if which gfortran-${i}>/dev/null && which gcc-${i}>/dev/null && which g++-${i}>/dev/null; then
	      install_gcc${i}=0
	   elif [[ "$has_spack" == "1" ]];
	      if ! spack find gcc@${i} | grep "No package matches the query"; then
   	      install_gcc${i}=0
	      fi
      fi
   fi
   if [[ "${install_gcc${i}}" == 1 ]]; then
      if [[ "$force_spack" == 1 ]]; then
         gcc_version=$(spack info gcc | grep -Eo " +${i}\.[[:digit:]]+\.[[:digit:]]+ " | head -n 1 | xargs)
         spack install gcc@${gcc_version}
      else
			add_ppa ubuntu-toolchain-r/test
			install_apt_packages gcc-${i} g++-${i} gfortran-${i}
			logexec sudo update-alternatives --install /usr/bin/g++ g++ $(which g++-${i}) 20
			logexec sudo update-alternatives --install /usr/bin/gcc gcc $(which gcc-${i}) 20
			logexec sudo update-alternatives --install /usr/bin/gfortran gfortran $(which gfortran-${i}) 20
      fi
   fi
done


if [[ "${has_spack}" == "1" ]]; then
	spack compiler find
fi

if [[ "${install_cmake}" == 1 ]]; then
   if which cmake>/dev/null; then
      install_cmake=0
   elif [[ "$has_spack" == "1" ]];
      if ! spack find cmake | grep "No package matches the query"; then
	      install_cmake=0
      fi
   fi
fi
if [[ "${install_cmake}" == 1 ]]; then
   if [[ "$force_spack" == 1 ]]; then
      spack install cmake
   else
      add_apt_source_manual kitware "deb https://apt.kitware.com/ubuntu/ $(get_ubuntu_codename) main" https://apt.kitware.com/keys/kitware-archive-latest.asc kitware-archive-latest.key
		install_apt_packages cmake
   fi
fi

#Adding github to known hosts
ssh-keyscan -H github.com | sudo -u ${USER} -- tee -a $home/.ssh/known_hosts

#Adding gitlab to known hosts:
ssh-keyscan -H git1.imgw.pl | sudo -u ${USER} -- tee -a $home/.ssh/known_hosts


