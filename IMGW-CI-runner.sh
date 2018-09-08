#!/bin/bash
cd `dirname $0`
. ./common.sh

usage="
Deploys installs all necessary requirements, clones, compiles and tests code, all as the current user

syntax:
$(basename $0) [--slack-username <name> --slack-token <string>]
		--git-address <path> --git-branch <branch> --repo-path <path> [--compile-using <compiler>]
		[--debug] [--log <log path>] [--help]


where

 --slack-enable             - Enables the slack integration with the default settings
 --slack-username           - Username for the slack client. Defaults to the hostname
 --slack-token              - Token for the communication with the slack server. Defaults to the slack
                              token created by Adam for the IMGWCH slack team.
 --git-address <path>       - Remote (read only) path to repository, which will be tested.
                              Defaults to «git@git.imgw.ad:aryczkowski/propoze.git»
 --git-branch <branch>      - Name of the branch to pull. Defaults to «develop».
 --repo-path <path>         - Place where the repository will be cloned
 --spack-location           - Name of the directory to install spack into. Defaults to ~/tmp/spack
 --spack-load <module>      - Package to preload with spack. If more than one module is needed,
                              put this option multiple times.
 --source-dir <path>        - Relative path to the source directory. Script will build this source in
                              created subdirectory \"build\". Defaults to the root of the repository.
 --debug                    - Flag. If set, all commands that change state of the container or
                              host machine will be displayed together with their output.
 --log                      - Redirects output from --debug into the log file.
 
Example:

$(basename $0) 
"

spack_load=()

if [ -z "$1" ]; then
	echo "$usage"
	exit 0
fi
slack_token="xoxp-107142650086-107156439191-194072196055-98a4c7330ee98cfb5544da16dc19f8fa"
slack_username=$(hostname)
sshhome=$(get_home_dir $USER)
spack_location=${sshhome}/tmp/spack
source_dir=""

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--git-address)
	git_address="$1"
	shift
	;;
	--git-branch)
	git_branch="$1"
	shift
	;;
	--repo-path)
	repo_path="$1"
	shift
	;;
	--slack-username)
	slack_username=$1
	shift
	;;
	--slack-token)
	slack_token="$1"
	shift
	;;
	--spack-load)
	spack_load+=($1)
	shift
	;;
	--spack-location)
	spack_location="$1"
	shift
	;;
	--source-dir)
	source_dir="$1"
	shift
	;;
	--debug)
	common_debug=1
	;;
	--log)
	log=$1
	shift
	;;
	--help)
	echo "$usage"
	exit 0
	;;
	*)
	errcho "Unkown parameter '$key'. Aborting."
	echo $usage
	exit 1
	;;
esac
done

#logexec sudo update-alternatives --install /usr/bin/python python /usr/bin/python3 10

#if [ -n "$compile_using" ]; then
#	if [ "$compile_using" != "cuda-9" ] && [ "$compile_using" != "gcc-5" ] && [ "$compile_using" != "gcc-6" ] && [ "$compile_using" != "gcc-7" ] && [ "$compile_using" != "clang-4" ] && [ "$compile_using" != "clang-5" ]; then
#		errcho "--compile-using must be one of the following: cuda-9, gcc-5, gcc-6, gcc-7, clang-4, clang-5"
#		exit 1
#	fi
#fi

invocation="cd \"${build_dir}\";"

if [ "${#spack_load[@]}" != "0" ]; then
	source "${spack_location}/share/spack/setup-env.sh"
	spack_sourced=1
	for spack_mod in "${spack_load[@]}"; do
		if spack find ${spack_mod} | grep -F "No package matches"; then
			logexec spack install ${spack_mod}
		fi
		spack load ${spack_mod}
		echo " LOADING ${spack_mod} USING SPACK!"
		invocation="${invocation} spack load ${spack_mod};"
	done
else
	spack_sourced=0
fi

#Check for essential dependencies
function check_for_dep {
	execname="$1"
	package="$2"
	if ! which $execname >/dev/null 2>/dev/null; then
		install_apt_package "$2"
	fi
}

check_for_dep gcc build-essential
check_for_dep g++ build-essential
check_for_dep gfortran gfortran
check_for_dep cmake cmake
check_for_dep python python

##Only the essential dependencies
#if [ -z "$compile_using" ]; then
#	install_apt_packages build-essential git
#	install_apt_package cmake cmake
#	build_dir="build"
#	cmake_args=""
#else
#	build_dir="build-${compile_using}"
#	if [ "$compile_using" == "cuda-9" ]; then
#		install_apt_packages build-essential gfortran git python3-pip
#		purge_apt_package cmake
#		if ! which "cmake">/dev/null  2> /dev/null; then
#			logmkdir /opt/sources ${USER}
#			pushd /opt/sources
#			if [ ! -f /opt/sources/cmake.tar.gz ]; then
#				wget -c https://cmake.org/files/v3.10/cmake-3.10.1.tar.gz --output-document=/opt/sources/cmake.tar.gz
#			fi
#			logexec sudo chown -R ${USER}:${USER} /opt/sources
#			logexec tar xf /opt/sources/cmake.tar.gz
#			logexec pushd cmake*
#			logexec ./bootstrap
#			logexec make -j 4
#			logexec sudo make install
#			logexec popd
#			logexec popd
#		fi
#		if install_apt_package_file /opt/sources/cuda-repo-ubuntu$(get_ubuntu_version)*.deb cuda-repo-ubuntu$(get_ubuntu_version); then
#			logexec sudo apt-key adv --fetch-keys http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/7fa2af80.pub
#			do_update force
#		fi
#		install_apt_package cuda-compiler-9-1 cuda-libraries-dev-9-1
#		cmake_args="-D USE_CUDA=1"
#	else
#		add_ppa ppa:ubuntu-toolchain-r/test
#		if [ "$compile_using" == "gcc-5" ]; then
#			cmake_args='-D CMAKE_C_COMPILER=$(which gcc-5) -D CMAKE_CXX_COMPILER=$(which g++-5) -D CMAKE_FORTRAN_COMPILER=$(which gfortran-5)'
#			install_apt_packages gcc-5 g++-5 gfortran-5
#			do_upgrade
#		elif [ "$compile_using" == "gcc-6" ]; then
#			cmake_args='-D CMAKE_C_COMPILER=$(which gcc-6) -D CMAKE_CXX_COMPILER=$(which g++-6) -D CMAKE_FORTRAN_COMPILER=$(which gfortran-6)'
#			install_apt_packages gcc-6 g++-6 gfortran-6
#		elif [ "$compile_using" == "gcc-7" ]; then
#			cmake_args='-D CMAKE_C_COMPILER=$(which gcc-7) -D CMAKE_CXX_COMPILER=$(which g++-7) -D CMAKE_FORTRAN_COMPILER=$(which gfortran-7)'
#			install_apt_packages gcc-7 g++-7 gfortran-7
#		elif [ "$compile_using" == "clang-4" ]; then
#			cmake_args='-D CMAKE_C_COMPILER=$(which clang-4.0) -D CMAKE_CXX_COMPILER=$(which clang++-4.0)'
#			install_apt_packages clang-4.0
#		elif [ "$compile_using" == "clang-5" ]; then
#			cmake_args='-D CMAKE_C_COMPILER=$(which clang-5.0) -D CMAKE_CXX_COMPILER=$(which clang++-5.0)'
#			install_apt_packages clang-5.0
#		elif [ "$compile_using" == "clang-3.8" ]; then
#			cmake_args='-D CMAKE_C_COMPILER=$(which clang-3.8) -D CMAKE_CXX_COMPILER=$(which clang++-3.8)'
#			install_apt_packages clang-3.8
#		else
#			errcho "Unkown compiler $compile_using"
#			exit 1
#		fi
#	fi
#fi

#Adding github to known hosts
logexec ssh-keyscan -H github.com >> $sshhome/.ssh/known_hosts

#Adding gitlab to known hosts:
logexec ssh-keyscan -H git.imgw.ad >> $sshhome/.ssh/known_hosts

#TODO: The following command can run in parallel to the next

if [ -d "${repo_path}/.git" ]; then
	pushd "$repo_path"
	logexec git pull --all
	logexec git checkout ${git_branch}
	logexec git submodule update
	popd
else
	logexec git clone --recursive --depth 1 ${git-address} "$repo_path" --branch $git_branch
fi

if [ ! -d "${repo_path}/${source_dir}" ]; then
	errcho "Cannot find path ${repo_path}/${source_dir}"
	exit 1
fi
build_dir="${repo_path}/${source_dir}/build"
logmkdir "$build_dir" ${USER}

logexec cd "$build_dir"

logexec rm "${build_dir}/apt_dependencies.txt" "${build_dir}/pip_dependencies.txt" "${build_dir}/spack_dependencies.txt"
logexec cmake .. ${cmake_args}
logexec rm "${build_dir}/CMakeCache.txt"


if [ ! -f "${build_dir}/apt_dependencies.txt" ]; then
	errcho "Some serious problem with project configuration"
	exit 1
fi

#xargs to trim the white spaces
app_deps=$(cat "${build_dir}/apt_dependencies.txt" | xargs) 
pip_deps=$(cat "${build_dir}/pip_dependencies.txt" | xargs)
spack_deps=$(cat "${build_dir}/pip_dependencies.txt" | xargs)

if [ -n "${app_deps}" ]; then
	install_apt_packages ${app_deps}
fi

if [ -n "${pip_deps}" ]; then
	sudo -H pip3 install ${pip_deps}
fi


if [ -n "${spack_deps}" ]; then
	if [ "$spack_sourced" != "1" ]; then
		source "${spack_location}/share/spack/setup-env.sh"
		spack_sourced=1
	fi
	for spack_mod in "${spack_deps[@]}"; do
		if spack find ${spack_mod} | grep -F "No package matches"; then
			logexec spack install ${spack_mod}
		fi
		spack load ${spack_mod}
		echo " LOADING ${spack_mod} USING SPACK!"
		invocation="${invocation} spack load ${spack_mod};"
	done
fi

cpu_cures=$(grep -c ^processor /proc/cpuinfo)

#rm "${repo_path}/${build_dir}/CMakeCache.txt"
#cd "${repo_path}/${build_dir}"
#cmake .. ${cmake_args} && make -j ${cpu_cures} && make test

byobu-tmux new-session -d -s ${build_dir} -n code "${invocation} cmake .. ${cmake_args} && make -j ${cpu_cures} && make test; bash"

