#!/bin/bash

## dependency: prepare_ubuntu.sh
## dependency: prepare_spack.sh

cd `dirname $0`
. ./common.sh

usage="
Prepares GitLab CI runner. Gitlab runner runs as 'gitlab-runner' user. 

syntax:
$(basename $0) [--runner-name <name>]
		[--gitlab-server <uri>] --gitlab-token <string>
		[--ssh-identity <path_private> <path_public>] 
		[--use-spack] [--spack-options \"opts\"]
		[--build-dir <path>] [--max-threads <N>] [--max-mem <MB>]
		[--debug] [--log <log path>] [--help]


where

 --gitlab-server <uri>      - Path to the gitlab server. Defaults to https://git1.imgw.pl
 --gitlab-token <string>    - Token that will allow access to the server. Required.
 --ssh-identity             - Path to the ssh identity files to be used by the gitlab-runner. 
     <path_prv> <path_pub>    Otherwise uses already present.
 --use-spack                - If given, the script will also prepare spack.
 --spack-options            - Options forwarded to the prepare_spack.sh script.
 --build-dir <path>         - Path to the build dir. Relative to the home of gitlab-runnet. Defaults to 'build'.
 --runner-name              - Name of the runner. Defaults to hostname.
 --max-mem <MB>             - Maximum number of MB allowed for build in this runner. 
                              This value will get written to the configuration file, and
                              used during CI run. Default to auto, which is
                              90% of (total mem - 1GB). 
 --max-threads <N>          - Max number of build threads allowed. Defaults to all
                              CPU threads available (\"auto\")
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
username=gitlab-runner
opts=""
env_opts=""
runner_name=$(hostname)
gitlab_server="https://git1.imgw.pl"
max_mem="auto"
max_threads="auto"
sudoprefix="sudo "
build_dir="auto"
use_spack=0
ssh_identity_source=""

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--use-spack)
	use_spack=1
	;;
	--spack-options)
	use_spack=1
	spack_options="$1"
	shift
	;;
	--gitlab-server)
	gitlab_server="$1"
	shift
	;;
	--gitlab-token)
	gitlab_token="$1"
	shift
	;;
	--runner-name)
	runner_name="$1"
	shift
	;;
	--ssh-identity)
	opts="${opts} --ssh-identity-file $1"
	ssh_identity_source_priv="$1"
	ssh_identity_source_pub="$2"
	shift
	shift
	;;
	--build-dir)
	build_dir="$1"
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


env_opts="${env_opts} CI_BUILD_DIR=${build_dir}"

if [ -z "${gitlab_token}" ]; then
	errcho "No --gitlab-token. It is a required argument."
	errcho $usage
fi

if [ "${max_mem}" != "auto" ]; then
	env_opts="${env_opts} MAX_MEM=${max_mem}"
fi

if [ "$max_threads" != "auto" ]; then
	env_opts="${env_opts} MAX_THREADS=${max_threads}"
fi

if [ ! -f "/etc/apt/sources.list.d/runner_gitlab-runner.list" ]; then
	wget https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh -O /tmp/script.deb.sh

	logexec sudo bash /tmp/script.deb.sh
fi

install_apt_package gitlab-runner gitlab-runner

if [[ -n "${username}" ]]; then
   sshhome=$(get_home_dir $username)
	if [ "$build_dir" == "auto" ]; then
		build_dir="${sshhome}/build"
		mkdir -p ${build_dir}
	else
   	logmkdir ${build_dir} gitlab-runner
		ln -s "${build_dir}" "${sshhome}/build"
		build_dir="${sshhome}/build"
	fi
else
   sshhome=$(get_home_dir)
	if [ "$build_dir" == "auto" ]; then
		build_dir="/opt/build"
		sudo mkdir -p ${build_dir}
	else
		sudo ln -s "${build_dir}" "/opt/build"
		build_dir="${sshhome}/build"
	fi
fi
logmkdir ${sshhome}/.gitlab-runner ${username}

if [ ! -f /usr/share/ca-certificates/extra/imgwpl.crt ]; then
	logexec logmkdir /usr/share/ca-certificates/extra
#	$loglog
   add_host_ssh_certificate git1.imgw.pl
   add_host_ssh_certificate github.com
   
#	echo -n | openssl s_client -connect git1.imgw.pl:443 | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' | sudo tee /usr/share/ca-certificates/extra/imgwpl.crt
#	linetextfile /etc/ca-certificates.conf extra/imgwpl.crt
#	logexec sudo update-ca-certificates
#	install_apt_package debconf-utils debconf-get-selections
fi

env_opts=$(echo ${env_opts} | xargs)
if [[ -n "$env_opts" ]]; then
	opts="$opts --env $env_opts"
fi

./prepare_ubuntu.sh gitlab-runner

if [[ $use_spack == 1 ]]; then
   ./prepare_spack.sh --user gitlab-runner ${spack_options}
fi

echo ${sudoprefix} gitlab-runner register --non-interactive --builds-dir "${build_dir}" --run-untagged --name "${runner_name}" --url  ${gitlab_server} --registration-token ${gitlab_token} --executor shell ${opts} --tls-ca-file=/usr/share/ca-certificates/extra/imgwpl.crt

logexec ${sudoprefix} gitlab-runner register --non-interactive  --builds-dir "${build_dir}" --run-untagged --name "${runner_name}" --url  ${gitlab_server} --registration-token ${gitlab_token} --executor shell ${opts} --tls-ca-file=/usr/share/ca-certificates/extra/imgwpl.crt

if [ -n "$ssh_identity_source_priv" ]; then
   install_data_file "${ssh_identity_source_priv}" $(get_home_dir gitlab-runner)/.ssh/id_ed25519 gitlab-runner
   install_data_file "${ssh_identity_source_pub}" $(get_home_dir gitlab-runner)/.ssh/id_ed25519.pub gitlab-runner
fi

##logexec sudo -H -u ${USER} -- gitlab-runner run &
#if [[ -n "${username}" ]]; then
#	#Adding github to known hosts
#	ssh-keyscan -H github.com | sudo -u ${username} -- tee -a ${sshhome}/.ssh/known_hosts

#	#Adding gitlab to known hosts:
#	ssh-keyscan -H git1.imgw.pl | sudo -u ${username} -- tee -a ${sshhome}/.ssh/known_hosts

#   logmkdir ${sshhome}/.gitlab-runner ${username}

##	logexec sudo -H -u ${username} -- byobu-tmux new-session -d -n code "gitlab-runner run; bash"
#fi
