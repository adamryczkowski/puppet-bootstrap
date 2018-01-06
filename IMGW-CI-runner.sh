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
 --compile-using <compiler> - Specify the compiler to use. 
                              Valid choices: 
                              * cuda-9
                              * gcc-5 (it will include gfortran-5)
                              * gcc-6 (it will include gfortran-6)
                              * gcc-7 (it will include gfortran-7)
                              * clang-4
                              * clang-5
                              Defaults to the gcc shipped with the system.
 --debug                    - Flag. If set, all commands that change state of the container or
                              host machine will be displayed together with their output.
 --log                      - Redirects output from --debug into the log file.
 
Example:

$(basename $0) 
"


if [ -z "$1" ]; then
	echo "$usage"
	exit 0
fi
slack_token="xoxp-107142650086-107156439191-194072196055-98a4c7330ee98cfb5544da16dc19f8fa"
slack_username=$(hostname)

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
	--compile-using)
	compile_using=$1
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

if [ -n "$compile_using" ]; then
	if [ "$compile_using" != "cuda-9" ] && [ "$compile_using" != "gcc-5" ] && [ "$compile_using" != "gcc-6" ] && [ "$compile_using" != "gcc-7" ] && [ "$compile_using" != "clang-4" ] && [ "$compile_using" != "clang-5" ]; then
		errcho "--compile-using must be one of the following: cuda-9, gcc-5, gcc-6, gcc-7, clang-4, clang-5"
		exit 1
	fi
fi


sshhome=`getent passwd $USER | awk -F: '{ print $6 }'`

#Only the essential dependencies
if [ -z "$compile_using" ]; then
	install_apt_packages build-essential git
	install_apt_package cmake cmake
	build_dir="build"
	cmake_args=""
else
	build_dir="build-${compile_using}"
	if [ "$compile_using" == "cuda-9" ]; then
		install_apt_packages build-essential gfortran git python3-pip
		purge_apt_package cmake
		if ! which "cmake">/dev/null  2> /dev/null; then
			logmkdir /opt/sources
			logexec pushd /opt/sources
			if [ ! -f /opt/sources/cmake.tar.gz ]; then
				wget -c https://cmake.org/files/v3.10/cmake-3.10.1.tar.gz
			fi
			logexec sudo chown -R ${USER}:${USER} /opt/sources
			logexec tar xf /opt/sources/cmake.tar.gz
			logexec pushd cmake*
			logexec ./bootstrap
			logexec make -j 4
			logexec sudo make install
			logexec popd
			logexec popd
		fi
		if install_apt_package_file /opt/sources/cuda-repo-ubuntu$(get_ubuntu_version)*.deb cuda-repo-ubuntu$(get_ubuntu_version); then
			do_update force
		fi
		install_apt_package cuda-compiler-9-1 cuda-libraries-dev-9-1
		cmake_args="-D USE_CUDA=1"
	else
		add_ppa ppa:ubuntu-toolchain-r/test
		if [ "$compile_using" == "gcc-5" ]; then
			cmake_args='-D CMAKE_C_COMPILER=$(which gcc-5) -D CMAKE_CXX_COMPILER=$(which g++-5) -D CMAKE_FORTRAN_COMPILER=$(which gfortran-5)'
			install_apt_packages gcc-5 g++-5 gfortran-5
			do_upgrade
		elif [ "$compile_using" == "gcc-6" ]; then
			cmake_args='-D CMAKE_C_COMPILER=$(which gcc-6) -D CMAKE_CXX_COMPILER=$(which g++-6) -D CMAKE_FORTRAN_COMPILER=$(which gfortran-6)'
			install_apt_packages gcc-6 g++-6 gfortran-6
		elif [ "$compile_using" == "gcc-7" ]; then
			cmake_args='-D CMAKE_C_COMPILER=$(which gcc-7) -D CMAKE_CXX_COMPILER=$(which g++-7) -D CMAKE_FORTRAN_COMPILER=$(which gfortran-7)'
			install_apt_packages gcc-7 g++-7 gfortran-7
		elif [ "$compile_using" == "clang-4" ]; then
			cmake_args='-D CMAKE_C_COMPILER=$(which clang-4.0) -D CMAKE_CXX_COMPILER=$(which clang++-4.0)'
			install_apt_packages clang-4.0
		elif [ "$compile_using" == "clang-5" ]; then
			cmake_args='-D CMAKE_C_COMPILER=$(which clang-5.0) -D CMAKE_CXX_COMPILER=$(which clang++-5.0)'
			install_apt_packages clang-5.0
		elif [ "$compile_using" == "clang-3.8" ]; then
			cmake_args='-D CMAKE_C_COMPILER=$(which clang-3.8) -D CMAKE_CXX_COMPILER=$(which clang++-3.8)'
			install_apt_packages clang-3.8
		else
			errcho "Unkown compiler $compile_using"
			exit 1
		fi
	fi
fi

#Adding github to known hosts
logexec ssh-keyscan -H github.com >> $sshhome/.ssh/known_hosts

#Adding gitlab to known hosts:
logexec ssh-keyscan -H git.imgw.ad >> $sshhome/.ssh/known_hosts

#TODO: The following command can run in parallel to the next

#logexec git clone --depth 1 --shallow-submodules git@git.imgw.ad:aryczkowski/propoze.git all --recursive "$repo_path"

if [ -d "${repo_path}/.git" ]; then
	pushd "$repo_path"
	logexec git pull
	logexec git checkout ${git_branch}
	logexec git submodule update
	popd
else
	logexec git clone --recursive --depth 1  git@git.imgw.ad:aryczkowski/propoze.git "$repo_path"
fi

logmkdir "$repo_path/$build_dir" ${USER}

logexec cd "$repo_path/$build_dir"

logexec rm "$repo_path/$build_dir/apt_dependencies.txt" "$repo_path/$build_dir/pip_dependencies.txt"
logexec cmake .. ${cmake_args}

if [ ! -f "$repo_path/$build_dir/apt_dependencies.txt" ]; then
	errcho "Some serious problem with project configuration"
	exit 1
fi

#xargs to trim the white spaces
app_deps=$(cat "$repo_path/$build_dir/apt_dependencies.txt" | xargs) 
pip_deps=$(cat "$repo_path/$build_dir/pip_dependencies.txt" | xargs)

if [ -n "${app_deps}" ]; then
	install_apt_packages ${app_deps}
fi

if [ -n "${pip_deps}" ]; then
	sudo -H pip3 install ${pip_deps}
fi

cpu_cures=$(grep -c ^processor /proc/cpuinfo)

byobu-tmux new-session -d -s $build_dir -n code "cd \"$repo_path/$build_dir\"; cmake .. ${cmake_args} && make -j ${cpu_cures} && make test; bash"

