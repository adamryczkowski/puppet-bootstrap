#!/bin/bash
cd `dirname $0`
. ./common.sh

usage="
Prepares GitLab CI runner

syntax:
$(basename $0) [--user <username>] [--runner-name <name>]
		[--gitlab-server <uri>] --gitlab-token <string>
		[--ssh-identity <path>]
		[--build-dir <path>] [--max-threads <N>] [--max-mem <MB>]
		[--debug] [--log <log path>] [--help]


where

 --user <username>          - Username which will run the CI
 --gitlab-server <uri>      - Path to the gitlab server. Defaults to https://git1.imgw.pl
 --gitlab-token <string>    - Token that will allow access to the server. Required.
 --build-dir <path>         - Path to the build dir. Optional parameter.
 --runner-name              - Name of the runner. Defaults to hostname.
 --max-mem <MB>             - Maximum number of MB allowed for build in this runner. 
                              This value will get written to the configuration file, and
                              used during CI run. Default to auto, which is
                              90% of (total mem - 1GB)
 --max-threads <N>          - Max number of build threads allowed. Defaults to all
                              CPU threads available (\"auto\")
 --ssh-identity <path>      - Path to the ssh identity file. Otherwise uses already present.
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
username="$USER"
opts=""
runner_name=$(hostname)
gitlab_server="https://git1.imgw.pl"
max_mem="auto"
max_threads="auto"

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--username)
	username="$1"
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
	shift
	;;
	--build-dir)
	opts="${opts} --builds-dir $1"
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

sshhome=$(get_home_dir $username)

if [ -z "${gitlab_token}" ]; then
	errcho "No --gitlab-token. It is a required argument."
	errcho $usage
fi

if [ "${max_mem}" == "auto" ]; then
	max_mem=$(($(grep MemTotal /proc/meminfo | awk '{print $2}'  )/1024))
fi

if [ "$max_threads" == "auto" ]; then
	max_threads=$(cat /proc/cpuinfo | awk '/^processor/{print $3}' | wc -l)
fi


invocation="cd \"${build_dir}\";"

if [ -f "/etc/apt/sources.list.d/runner_gitlab-runner.list"]
	wget https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh -O /tmp/script.deb.sh

	loglxc bash /tmp/script.deb.sh
fi

apt-install_apt_package gitlab-runner gitlab-runner

logexec gitlab-runner register --non-interactive --run-untagged --name "${runner_name}" --url  ${gitlab_server} --token ${gitlab_token} --executor shell ${opts} --env "MAX_MEM=${max_mem} MAX_THREADS=${max_threads}"

