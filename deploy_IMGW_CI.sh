#!/bin/bash

## dependency: softether-client.sh
## dependency: make-lxd-node.sh
## dependency: prepare_GitLab_CI_runner.sh

## dependency: prepare_spack.sh
## dependency: IMGW-CI-runner.sh
cd `dirname $0`
. ./common.sh


usage="
Prepares container that can do CI of the PROPOZE project


Usage:

$(basename $0) <container_name> --gitlab-token <string> [--softether-password <vpn-password>]
		[--grant-sudo] [--make-lxd-node-opts \"opts\"] [--max-threads <N>] [--max-mem <MB>]
		[--ssh-key-path <path>] [--host-repo-path <path>] [--guest-repo-path <path>]
		[--release <release_name>] [--apt-proxy <proxy_address>] [--preinstall-spack <package> ...]
		[--preinstall-apt <package>...]
		[--help] [--debug] [--log <output file>]


where
 <container_name>              - Name of the (LXC) container that will hold the CI runner
 --gitlab-token <string>       - Token that will allow access to the server. Required.
 --softether-password          - Softether password. Username is fixed to the container_name. 
                                 Hub is fixed to IMGW. If skept, no softether is installed.
 --grant-sudo                  - Flag that gives passwordless sudo priviledge to the gitlab-runner.
 --make-lxd-node-opts \"<opts>\"  - Options that will be forwarded to the make-lxd-node script.
 --max-mem <MB>                - Maximum number of MB allowed for build in this runner. This limit will be
                                 enforced using hard memory limit on the container and 
                                 this value will get written to the configuration file to be
                                 used during CI run. Default to auto, which is
                                 90% of (total mem - 1GB). 
 --max-threads <N>             - Max number of build threads allowed. Defaults to all
                                 CPU threads available (\"auto\"). This is a hard limit enforced on the container.
 --ssh-key-path <path>         - Path to the ssh private key that allows pulling the source code.
                                 Most likely the deploy key. Otherwise it will install a new keypair,
                                 and you will need to add this keypair to GitLab & GitHub.
 --guest-repo-path <path>      - Build path in the container. It will be owned by the gitlab-runner user.
                                 Defaults to /opt/CI
 --host-repo-path <path>       - Location of the build path in the host. If not specified, the build path
                                 will be visible only to the guest OS.
 --release <release_name>      - What Ubuntu flavour to test? Defaults to the current distro.
 --apt-proxy <proxy_address>   - Address of the existing apt-cacher with port, e.g. 192.168.1.0:3142. Defaults to the
                                 already existing caching on the host.
 --force-spack                 - If set the dependencies will be installed using spack rather apt.
 --preinstall-spack            - Name of the package to pre-install using spack
                                 (e.g. --preinstall-spack cmake --preinstall-spack gcc@6.4.0)
 --spack_mirror                - Location of local spack mirror. Mirror will be shared with the container.
                                 Needed only, when --preinstall-spack any package.
 --repo-path                   - Path to the local repository of files, e.g. /media/adam-minipc/other/debs
 --preinstall-apt              - Name of the packages to pre-install using package manager
 --debug                       - Flag that sets debugging mode. 
 --log                         - Path to the log file that will log all meaningful commands


Example2:

$(basename $0) gitrunner8 --softether-password 1WTh3yAjAkXaQmiOz105 --ssh-key-path secrets/gitlab_ssh_key --host-repo-path /home/Adama-docs/Lib/CI --preinstall-spack cmake --preinstall-apt gcc-8 --preinstall-apt g++-8 --preinstall-apt gfortran-8 --gitlab-token ENMnScUBNMFDJqjQ8N9z
"

if [[ -z "$1" ]] ||  [[ "$1" == "--help" ]] ; then
	echo "$usage"
	exit 0
fi
container_name=$1
shift

CI_opts=""
makelxd_opts=""
build_dir=/opt/build

use_softether=0
grant_sudo=0
max_mem="auto"
max_threads=""
ssh_key_path=""
guest_path="/opt/CI"
host_path=""
release=$(get_ubuntu_codename)
release_opts=""
aptproxy="auto"
force_spack=0
install_spack=0
spack_opts=""
if mount_network_cache; then
   repo_path=/media/adam-minipc/other/debs
else
   repo_path=""
fi
repo_path_opts="--repo-path $1"

apt_packages=()


while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--gitlab-token)
	gitlab_token="$1"
	shift
	;;
	--debug)
	debug=1
	;;
	--softether-password)
	softether_password=$1
	use_softether=1
	softether_username=$container_name
	shift
	;;
	--grant-sudo)
	grant_sudo=1
	;;
	--make-lxd-node-opts)
	makelxd_opts="$makelxd_opts $1"
	shift
	;;
	--max-mem)
	max_mem="$1"
	shift
	;;
	--max-threads)
	max_threads="$1"
	shift
	;;
	--ssh-key-path)
	ssh_key_path=$1
	shift
	;;
	--guest-repo-path)
	guest_path=$1
	shift
	;;
	--host-repo-path)
	host_path=$1
	shift
	;;
	--release)
	makelxd_opts="$makelxd_opts --release $1"
	shift
	;;
	--apt-proxy)
	aptproxy=$1
	shift
	;;
	--force-spack)
   force_spack=1
   install_spack=1
   ;;
	--preinstall-spack)
	spack_opts="${spack_opts} --pre-install $1"
	CI_opts="${CI_opts} --spack-load $1"
	install_spack=1
	shift
	;;
	--spack-mirror)
	spack_opts="${spack_opts} --spack-mirror $1"
	makelxd_opts="${makelxd_opts} --map-host-folder $1 $1"
	shift
	;;
#	--repo-path)
#	repo_path_opts="--repo-path $1"
#	shift
#	;;
	--preinstall-apt)
	apt_packages+=($1)
	shift
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
	*)
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

if [ -n "$ssh_key_path" ]; then
	if [ ! -f "$ssh_key_path" ]; then
		errcho "Cannot find a key specified in the --ssh-key-path"
		exit 1
	fi
fi

opts=""

if [[ "$aptproxy" == "auto" ]]; then
   aptproxy=$(get_apt_proxy)
fi

if [ -n "$aptproxy" ]; then
	makelxd_opts="${makelxd_opts} --apt-proxy ${aptproxy} "
fi

if [ -n "$host_path" ]; then
	logmkdir "$host_path" ${USER}
fi

if [ -n "$debug" ]; then
	opts="${opts}--debug "
fi

if [[ "$max_mem" == "auto" ]]; then
   max_mem=$(echo "($(get_total_mem_MB)-1024)*0.9" | bc)
fi

# First we make the container
./make-lxd-node.sh ${container_name} ${makelxd_opts} --bare

#get the IP of the running container
container_ip=$(lxc exec $container_name --mode=non-interactive -- ifconfig eth0 | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')

#Add limits to the container
if [ -n "$max_mem" ]; then
   logexec lxc config set $container_name limits.memory ${max_mem}MB
fi

if [ -n "$max_threads" ]; then
   logexec lxc config set $container_name limits.cpu $max_threads
fi

logexec lxc config set $container_name limits.cpu.priority 0

# Then we install the VPN network (optionally)

if [ -n "$softether_password" ]; then
	./execute-script-remotely.sh softether-client.sh --ssh-address ${container_ip} $external_opts -- 172.104.148.166 --username ${container_name} --password ${softether_password} --vpn-hub IMGW --nicname imgw
fi

./execute-script-remotely.sh prepare_GitLab_CI_runner.sh --extra-executable secrets/gitlab_ssh_key --extra-executable secrets/gitlab_ssh_key.pub --ssh-address ${container_ip} $external_opts -- --gitlab-token ${gitlab_token} --ssh-identity gitlab_ssh_key gitlab_ssh_key.pub --build-dir ${build_dir}

./execute-script-remotely.sh prepare_ubuntu.sh --ssh-address ${container_ip} $external_opts -- 


lxc file push secrets/deploy_git.key ${container_name}/home/gitlab-runner/.ssh/id_ed25519
lxc exec ${container_name} --mode=non-interactive chmod 0700 /home/gitlab-runner/.ssh/id_ed25519
lxc exec ${container_name} --mode=non-interactive chown gitlab-runner:gitlab-runner /home/gitlab-runner/.ssh/id_ed25519

if [ "$install_spack" != 0 ]; then
	./execute-script-remotely.sh prepare_spack.sh --ssh-address ${container_ip} $external_opts --step-debug --  ${opts} ${spack_opts}
fi

./execute-script-remotely.sh prepare_for_imgw.sh --ssh-address ${container_ip} $external_opts -- --gcc 8

if [ -n "$host_path" ]; then
	if ! lxc config device show ${container_name} | grep -q repo_${container_name}; then
		if ! lxc exec ${container_name} --mode=non-interactive -- ls ${guest_path}; then
			logexec lxc exec ${container_name} --mode=non-interactive -- mkdir -p ${guest_path}
			logexec lxc exec ${container_name} --mode=non-interactive -- chown ${USER} ${guest_path}
		fi
		logexec lxc config device add ${container_name} repo_${container_name} disk source="${host_path}" path=${guest_path}
	fi
fi

if [ "$apt_opts" != "" ]; then
	./execute-script-remotely.sh install_apt_packages.sh --ssh-address ${container_ip} $external_opts --step-debug --  ${apt_opts}
fi

