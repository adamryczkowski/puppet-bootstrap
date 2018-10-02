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
env_opts=""
runner_name=$(hostname)
gitlab_server="https://git1.imgw.pl"
max_mem="auto"
max_threads="auto"

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--user)
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
	build_dir="$1"
	env_opts="${env_opts} BUILD_DIR=$1"
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

if [ "${max_mem}" != "auto" ]; then
	env_opts="${env_opts} MAX_MEM=${max_mem}"
fi

if [ "$max_threads" != "auto" ]; then
	env_opts="${env_opts} MAX_THREADS=${max_threads}"
fi

if [ ! -f "/etc/apt/sources.list.d/runner_gitlab-runner.list" ]; then
	wget https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh -O /tmp/script.deb.sh

	logexec bash /tmp/script.deb.sh
fi

install_apt_package gitlab-runner gitlab-runner

if [ ! -f /usr/share/ca-certificates/extra/imgwpl.crt ]; then
	logexec logmkdir /usr/share/ca-certificates/extra
#	$loglog
	echo -n | openssl s_client -connect git1.imgw.pl:443 | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' | sudo tee /usr/share/ca-certificates/extra/imgwpl.crt
	linetextfile /etc/ca-certificates.conf extra/imgwpl.crt
	logexec sudo update-ca-certificates
#	install_apt_package debconf-utils debconf-get-selections
#	current=$(debconf-get-selections |grep ca-certificates/enable_crts)
#	pattern='^(ca-certificates	ca-certificates/enable_crts	multiselect)	(.*)$'
#	if ! [[ "$current" =~ $pattern ]]; then
#		echo "ERROR"
#		exit 1
#	fi
#	tmp=$(mktemp)
#	echo "${BASH_REMATCH[1]} extra/imgwpl.crt, ${BASH_REMATCH[2]}">$tmp
#	logexec sudo debconf-set-selections $tmp
#	rm $tmp
fi


logexec gitlab-runner register --non-interactive --run-untagged --name "${runner_name}" --url  ${gitlab_server} --registration-token ${gitlab_token} --executor shell ${opts} --env "${env_opts}" 


