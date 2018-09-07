#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Prepares container that can do CI of the PROPOZE project


Usage:

$(basename $0) <container_name> [--vpn-password <vpn-password> --vpn-username <vpn-username>]
		[--git-address <address of the repo>] [--git-branch <branch>] 
		[--ssh-key-path <path>] [--host-repo-path <path>] [--guest-repo-path <path>]
		[--release <release_name>] [--compile-using <compiler>]
		[--help] [--debug] [--log <output file>]


where
 <container_name>              - Name of the (LXC) container that will hold the CI runner
 --vpn-password <vpn-password> - If specified, it will also install a service that connects 
 --vpn-username <vpn-username> - with the IMGW VPN using theese credentials
 --git-address <path>          - Remote (read only) path to repository, which will be tested.
                                 Defaults to «git@git.imgw.ad:aryczkowski/propoze.git»
 --git-branch <branch>         - Name of the branch to pull. Defaults to «develop».
 --ssh-key-path <path>         - Path to the ssh private key that allows pulling the source code
 --host-repo-path <path>       - Local path to the pulled repository. If no files in the path,
                                 the script will pull the code.
 --guest-repo-path <path>      - Where the repository will be available in the guest.
                                 Defaults to «~/propoze»
 --source-dir <path>           - Relative path to the source directory. Script will build this source in
                                 created subdirectory \"build\". Defaults to the root of the repository.
 --release <release_name>      - What Ubuntu flavour to test? Defaults to the current distro.
 --apt-proxy <proxy_address>   - Address of the existing apt-cacher with port, e.g. 192.168.1.0:3142.
 --preinstall-spack            - Name of the package to pre-install using spack
                                 (e.g. --preinstall-spack cmake --preinstall-spack gcc@6.4.0)
 --repo-path                   - Path to the local repository of files, e.g. /media/adam-minipc/other/debs
 --spack-location              - Name of the directory to install spack into. Defaults to ~/tmp/spack
                                 Needed only, when --preinstall-spack any package.
 --spack_mirror                - Location of local spack mirror. Mirror will be shared with the container.
                                 Needed only, when --preinstall-spack any package.
 --preinstall-apt              - Name of the packages to pre-install using package manager
 --debug                       - Flag that sets debugging mode. 
 --log                         - Path to the log file that will log all meaningful commands


Example2:

$(basename $0) runner1 --vpn-username aryczkowski --vpn-password Qwer12345679 --ssh-key-path ~/.ssh/id_rsa --host-repo-path ~/CI1 --debug
"

if [ -z "$1" ]; then
	echo "$usage"
	exit 0
fi
container_name=$1
git_address='git@git.imgw.ad:aryczkowski/propoze.git'
git_branch='develop'
guest_path="/home/${USER}/propoze"
release=xenial
spack_opts=""
install_spack=0
apt_opts=""
repo_path_opts=""

shift

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
	--repo-path)
	repo_path_opts="--repo-path $1"
	shift
	;;
	--vpn-password)
	vpn_password=$1
	shift
	;;
	--vpn-username)
	vpn_username=$1
	shift
	;;
	--git-address)
	git_address=$1
	shift
	;;
	--git-branch)
	git_branch=$1
	shift
	;;
	--ssh-key-path)
	ssh_key_path=$1
	shift
	;;
	--host-repo-path)
	host_path=$1
	shift
	;;
	--guest-repo-path)
	guest_path=$1
	shift
	;;
	--source-dir)
	CI_opts="${CI_opts} --source-dir $1"
	shift
	;;
	--release)
	release=$1
	shift
	;;
	--apt-proxy)
	aptproxy=$1
	shift
	;;
	--preinstall-spack)
	spack_opts="${spack_opts} --pre-install $1"
	install_spack=1
	shift
	;;
	--spack-location)
	spack_opts="${spack_opts} --spack-location $1"
	shift
	;;
	--spack-mirror)
	spack_opts="${spack_opts} --spack-mirror $1"
	makelxd_opts="${makelxd_opts} --map-host-folder $1 $1"
	shift
	;;
	--preinstall-apt)
	apt_opts="${apt_opts} $1"
	shift
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
	external_opts="--debug --step-debug"
fi

if [ -n "$vpn_password" ] && [ -n "$vpn_username" ]; then
	flag_install_vpn=1
elif [ -z "$vpn_password" ] && [ -z "$vpn_username" ]; then
	flag_install_vpn=0
else
	errcho "You must either privde both --vpn-username --vpn-password or none."
	exit 1
fi

if [ -n "$ssh_key_path" ]; then
	if [ ! -f "$ssh_key_path" ]; then
		errcho "Cannot find a key specified in the --ssh-key-path"
		exit 1
	fi
fi

opts=""

if [ -n "$release" ]; then
	opts="${opts}--release ${release} "
fi

if [ -n "$aptproxy" ]; then
	opts="${opts}--apt-proxy ${aptproxy} "
fi

if [ -n "$ssh_key_path" ]; then
	opts="${opts}--private-key-path ${ssh_key_path} "
fi

if [ -n "$host_path" ]; then
	logmkdir "$host_path" ${USER}
	opts="${opts}--map-host-user ${USER} "
fi

if [ -n "$debug" ]; then
	opts="${opts}--debug "
fi

# First we make the container
./make-lxd-node.sh ${container_name} ${opts} ${repo_path_opts}

#get the IP of the running container
container_ip=$(lxc exec $container_name -- ifconfig eth0 | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')

# Then we install the VPN network (optionally)

if [ -n "$vpn_username" ]; then
	if [ -z "$vpn_password" ]; then
		errcho "You must provide password"
		exit 1
	else
		./execute-script-remotely.sh IMGW-VPN.sh --ssh-address ${container_ip} $external_opts --step-debug -- ${vpn_username}@vpn.imgw.pl --password ${vpn_password}
	fi
fi

# Now we can clone the repo and install its dependencies
opts=""
#if [ -n "$compile_using" ]; then
#	opts="${opts}--compile-using ${compile_using}"
#fi
#if [ "$compile_using" == "cuda-9" ]; then
#	lxc exec ${container_name} /bin/mkdir -p /opt/sources
#	lxc file push ~/tmp/debs/cmake-3.9* ${container_name}/opt/sources/cmake.tar.gz
#	if [ "$release" == "xenial" ]; then
#		if [ ! -f "~/tmp/debs/cuda-repo-ubuntu1604*" ]; then
#			logmkdir ~/tmp/debs ${USER}
#			logexec pushd ~/tmp/debs
#			logexec wget -c http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/cuda-repo-ubuntu1604_9.1.85-1_amd64.deb
#			logexec popd
#		fi
#		lxc file push ~/tmp/debs/cuda-repo-ubuntu1604*.deb ${container_name}/opt/sources/
#	elif [ "$release" == "zesty" ]; then
#		if [ ! -f "~/tmp/debs/cuda-repo-ubuntu1704*" ]; then
#			logexec pushd ~/tmp/debs
#			logexec wget -c http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1704/x86_64/cuda-repo-ubuntu1704_9.1.85-1_amd64.deb
#			logexec popd
#		fi
#		lxc file push ~/tmp/debs/cuda-repo-ubuntu1704*.deb ${container_name}/opt/sources/
#	else
#		errcho "Ubuntu $release is not supported by NVidia CUDA"
#		exit 1
#	fi
#fi

if [ -n "$host_path" ]; then
	if ! lxc config device show ${container_name} | grep -q repo_${container_name}; then
		logexec lxc config device add ${container_name} repo_${container_name} disk source="${host_path}" path=${guest_path}
	fi
fi

if [ "$apt_opts" != "" ]; then
	./execute-script-remotely.sh install_apt_packages.sh --ssh-address ${container_ip} $external_opts --step-debug --  ${apt_opts}
fi

if [ "$install_spack" != 0 ]; then
	./execute-script-remotely.sh prepare_spack.sh --ssh-address ${container_ip} $external_opts --step-debug --  ${opts} ${spack_opts}
fi

./execute-script-remotely.sh IMGW-CI-runner.sh --ssh-address ${container_ip} $external_opts --step-debug -- --git-address "${git_address}" --git-branch "${git_branch}" --repo-path "${guest_path}" ${opts} ${CI_opts}


