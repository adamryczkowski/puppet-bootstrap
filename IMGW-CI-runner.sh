#!/bin/bash
cd `dirname $0`
. ./common.sh

usage="
Deploys installs all necessary requirements, clones, compiles and tests code, all as the current user

syntax:
$(basename $0) [--slack-username <name> --slack-token <string>]
		--git-address <path> --git-branch <branch> --repo-path <path>
		[--debug] [--log <log path>] [--help]


where

 --slack-enable           - Enables the slack integration with the default settings
 --slack-username         - Username for the slack client. Defaults to the hostname
 --slack-token            - Token for the communication with the slack server. Defaults to the slack
                            token created by Adam for the IMGWCH slack team.
 --git-address <path>     - Remote (read only) path to repository, which will be tested.
                            Defaults to «git@git.imgw.ad:aryczkowski/propoze.git»
 --git-branch <branch>    - Name of the branch to pull. Defaults to «develop».
 --repo-path <path>       - Place where the repository will be cloned
 --debug                  - Flag. If set, all commands that change state of the container or
                            host machine will be displayed together with their output.
 --log                    - Redirects output from --debug into the log file.
 
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


sshhome=`getent passwd $USER | awk -F: '{ print $6 }'`

#Only the essential dependencies
install_apt_packages cmake build-essential gfortran git

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

logmkdir "$repo_path/build" ${USER}

logexec cd "$repo_path/build"

logexec rm "$repo_path/build/apt_dependencies.txt" "$repo_path/build/pip_dependencies.txt"
logexec cmake ..

if [ ! -f "$repo_path/build/apt_dependencies.txt" ]; then
	errcho "Some serious problem with project configuration"
	exit 1
fi

#xargs to trim the white spaces
app_deps=$(cat "$repo_path/build/apt_dependencies.txt" | xargs) 
pip_deps=$(cat "$repo_path/build/pip_dependencies.txt" | xargs)

if [ -n "${app_deps}" ]; then
	install_apt_packages ${app_deps}
fi

if [ -n "${pip_deps}" ]; then
	sudo -H pip3 install ${pip_deps}
fi

if [ -n "${app_deps}" ] || [ -n "${pip_deps}" ]; then
	logexec cmake ..
fi

byobu-tmux new-session -d -s build -n code 'cd "$repo_path/build"; make && make test; bash'

