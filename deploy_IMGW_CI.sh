#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Prepares container that can do CI of the PROPOZE project


Usage:

$(basename $0) <container_name> [--vpn-password <vpn-password> --vpn-username <vpn-username>]
		[--git-address <address of the repo>] [--git-branch <branch>] 
		[--ssh-key-path <path>] [--host-repo-path <path>] [--guest-repo-path <path>]
		[--release <release_name>]
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
 --release <release_name>      - What Ubuntu flavour to test? Defaults to the current distro.
 --apt-proxy <proxy_address>   - Address of the existing apt-cacher with port, e.g. 192.168.1.0:3142.
 --debug                       - Flag that sets debugging mode. 
 --log                         - Path to the log file that will log all meaningful commands


Example2:

$(basename $0) ci_runner_1 --vpn-username aryczkowski --vpn-password Qwer12345679 --ssh-key-path ~/.ssh/id_rsa --host-repo-path ~/CI1 --debug
"

if [ -z "$1" ]; then
	echo "$usage"
	exit 0
fi
container_name=$1
git_address='git@git.imgw.ad:aryczkowski/propoze.git'
git_branch='develop'
guest_path='~/propoze'

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
	--release)
	release=$1
	shift
	;;
	--apt-proxy)
	aptproxy=$1
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
	logmkdir "$host_path"
	opts="${opts}--map-host-user ${USER} "
fi

if [ -n "$debug" ]; then
	opts="${opts}--debug "
fi

# First we make the container
./execute-script-remotely.sh make-lxd-node.sh --ssh-address ${USER}@localhost $external_opts -- ${container_name} ${opts}

#get the IP of the running container
container_ip=$(lxc exec $container_name -- ifconfig eth0 | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')



# Then we install the VPN network (optionally)

if [ -z "$vpn_password" ]; then
	errcho "You must provide password"
	exit 1
fi

if [ -n "$vpn_password" ]; then
	./execute-script-remotely.sh IMGW-VPN.sh --ssh-address ${container_ip} $external_opts -- ${vpn_username}@vpn.imgw.pl --password ${vpn_password}
fi

# Now we can clone the repo and install its dependencies

./execute-script-remotely.sh IMGW-CI-runner.sh --ssh-address ${container_ip} $external_opts -- --git-address "${git_address}" --git-branch "${git_branch}" --repo-path "${guest_path}"

if [ -n "$host_path" ]; then
	if ! lxc config device show ${container_name} | grep -q repo_${container_name}; then
		logexec lxc config device add ${container_name} repo_${container_name} disk source="${host_path}" path=${guest_path}
	fi
fi

