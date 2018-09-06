#!/bin/bash
cd `dirname $0`
. ./common.sh

usage="
Enhances bare-bones Ubuntu installation with several tricks. 
It adds a new user,
fixes locale,
installs byobu, htop and mcedit

The script must be run as a root.

Usage:

$(basename $0) <user-name> [--apt-proxy IP:PORT] [--wormhole] [--need-apt-update]

where

 --wormhole               - Install magic wormhole (app for easy sending files)
 -p|--apt-proxy           - Address of the existing apt-cacher with port, e.g. 192.168.1.0:3142.
 --need-apt-update        - If the flag is set the script will assume the apt cache needs apdate. 
 --private_key_path       - This argument gets handled to 'prepare_ubuntu_user' for the first given user.
 --external-key <string>  - Sets external public key to access the account. It
                            populates authorized_keys
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands
 --repo-path              - Path to the common repository
 --user <username>        - Additional user to install the tricks to. Can be specified
                            multiple times, each time adding another user.
 --cli_improved           - Install all the following recommended command line tools:
 --bat                    - cat replacement (bat)
 --ping                   - prettyping (ping),
 --fzf                    - fzf (for bash ctr+r)
 --htop                   - htop
 --diff                   - diff-so-fancy (diff),
 --find                   - fd (replaces find)
 --du                     - ncdu (replaces du), 
 --tldr                   - tldr,
 --ag                     - ag (the silver searcher), 
 --entr                   - entr (watch), 
 --noti                   - noti (notification when something is done)
 --mc                     - mc (Midnight Commander)
 --liquidprompt           - liquidprompt
 --byobu                  - byobu
 --autojump               - autojump (cd replacement)

Example:

$(basename $0) --apt-proxy 192.168.10.2:3142
"

dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}
mypath=${0%/*}
mypath=`dir_resolve $mypath`
cd $mypath

users=()
pattern='^--.*$'
if [[ ! "$1" =~ $pattern ]]; then
	users+=("$1")
	shift
fi

debug=0
wormhole=0
repo_path=""
install_bat=0
install_ping=0
install_fzf=0
install_htop=0
install_diff=0
install_find=0
install_du=0
install_tldr=0
install_ag=0
install_entr=0
install_noti=0
install_mc=0
install_liquidprompt=0
install_byobu=0
install_autojump=0

user_opts=""

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--debug)
	debug=1
	;;
	--help)
        echo "$usage"
        exit 0
	;;
	--log)
	log=$1
	shift
	;;
	--repo-path)
	repo_path="$1"
	shift
	;;
	--apt-proxy)
	aptproxy=$1
	shift
	;;
	--external-key)
	user_opts="${--external-key} $1"
	shift
	;;
	--private-key-path)
	private_key_path="--private-key-path $1"
	shift
	;;
	--users)
	users+=("$1")
	shift
	;;
	--wormhole)
	wormhole=1
	;;
	--need-apt-update)
	flag_need_apt_update=1
	;;
	--cli_improved)
	install_bat=1
	user_opts="${user_opts} --bat"
	install_ping=1
	user_opts="${user_opts} --ping"
	install_fzf=1
	user_opts="${user_opts} --fzf"
	install_htop=1
	install_diff=1
	user_opts="${user_opts} --diff"
	install_find=1
	install_du=1
	user_opts="${user_opts} --du"
	install_tldr=1
	install_ag=1
	install_entr=1
	install_noti=1
	install_mc=1
	install_liquidprompt=1
	user_opts="${user_opts} --liquidprompt"
	install_byobu=1
	install_autojump=1
	user_opts="${user_opts} --autojump"
	;;
	--bat)
	install_bat=1
	user_opts="${user_opts} --bat"
	;;
	--ping)
	install_ping=1
	user_opts="${user_opts} --ping"
	;;
	--fzf)
	install_fzf=1
	user_opts="${user_opts} --fzf"
	;;
	--htop)
	install_htop=1
	;;
	--diff)
	install_diff=1
	user_opts="${user_opts} --diff"
	;;
	--find)
	install_find=1
	;;
	--du)
	install_du=1
	user_opts="${user_opts} --du"
	;;
	--tldr)
	install_tldr=1
	;;
	--ag)
	install_ag=1
	;;
	--entr)
	install_entr=1
	;;
	--noti)
	install_noti=1
	;;
	--mc)
	install_mc=1
	;;
	--liquidprompt)
	install_liquidprompt=1
	user_opts="${user_opts} --liquidprompt"
	;;
	--byobu)
	install_byobu=1
	;;
	--autojump)
	install_autojump=1
	user_opts="${user_opts} --autojump"
	;;
    -*)
    echo "Error: Unknown option: $1" >&2
    echo "$usage" >&2
    ;;
esac
done

users+=("$USER")

if [ -n "$debug" ]; then
	if [ -z "$log" ]; then
		log=/dev/stdout
	fi
fi

if ! sudo -n true 2>/dev/null; then
    errcho "User $USER doesn't have admin rights"
    exit 1
fi

if [ -n "$aptproxy" ]; then
	$loglog
	echo "Acquire::http::Proxy \"http://$aptproxy\";" | sudo tee /etc/apt/apt.conf.d/90apt-cacher-ng >/dev/null
	flag_need_apt_update=1
fi


if ! grep -q LC_ALL /etc/default/locale 2>/dev/null; then
sudo tee /etc/default/locale <<EOF
LANG="en_US.UTF-8"
LC_ALL="en_US.UTF-8"
EOF
	logexec sudo locale-gen en_US.UTF-8
	logexec sudo locale-gen pl_PL.UTF-8
fi

do_update
do_upgrade

install_apt_packages bash-completion

#	install_byobu=1

if [ "${install_bat}" == "1" ]; then
	install_apt_package_file bat_0.6.1_amd64.deb bat https://github.com/sharkdp/bat/releases/download/v0.6.1/bat_0.6.1_amd64.deb
fi

if [ "${install_ping}" == "1" ]; then
	plik=$(get_cached_file prettyping https://raw.githubusercontent.com/denilsonsa/prettyping/master/prettyping)
	install_script "${plik}" /usr/local/bin/prettyping root
fi

if [ "${install_fzf}" == "1" ]; then
	get_git_repo https://github.com/junegunn/fzf.git /usr/local/lib 
	logexec sudo /usr/local/lib/fzf/install --all --xdg
fi

if [ "${install_htop}" == "1" ]; then
	install_apt_package htop
fi

if [ "${install_diff}" == "1" ]; then
	plik=$(get_cached_file diff-so-fancy https://raw.githubusercontent.com/so-fancy/diff-so-fancy/master/third_party/build_fatpack/diff-so-fancy)
	install_script "${plik}" /usr/local/bin/diff-so-fancy
	
fi

if [ "${install_find}" == "1" ]; then
	install_apt_package_file fd-musl_7.1.0_amd64.deb fd https://github.com/sharkdp/fd/releases/download/v7.1.0/fd-musl_7.1.0_amd64.deb
fi

if [ "${install_du}" == "1" ]; then
	get_cached_file ncdu.tar.gz https://dev.yorhel.nl/download/ncdu-1.13.tar.gz
	tmp=$(mktemp -d)
	uncompress_cached_file ncdu.tar.gz $tmp
	install_apt_packages build-essential libncurses5-dev
	logexec pushd ${tmp}/ncdu-1.13
	logexec ./configure
	logexec make
	logexec sudo make install
	logexec popd
fi

if [ "${install_tldr}" == "1" ]; then
	install_apt_packages python3-pip
	install_pip3_packages tldr
fi

if [ "${install_ag}" == "1" ]; then
	install_apt_package silversearcher-ag
fi

if [ "${install_entr}" == "1" ]; then
	get_cached_file entr-4.1.tar.gz http://entrproject.org/code/entr-4.1.tar.gz
	tmp=$(mktemp -d)
	uncompress_cached_file entr-4.1.tar.gz $tmp
	logexec pushd ${tmp}/eradman-entr-f4e2cbe57708
	install_apt_packages build-essential
	logexec ./configure
	logexec make
	logexec sudo make install
	logexec popd
fi

if [ "${install_noti}" == "1" ]; then
	install_apt_packages golang-go
	go get -u github.com/variadico/noti/cmd/noti
fi

if [ "${install_mc}" == "1" ]; then
	install_apt_package mc
fi

if [ "${install_liquidprompt}" == "1" ]; then
	install_apt_packages liquidprompt
	logexec sudo -H liquidprompt_activate
fi

if [ "${install_byobu}" == "1" ]; then
	install_apt_package byobu
fi

if [ "${install_autojump}" == "1" ]; then
	install_apt_package autojump
fi

if [ "${wormhole}" == "1" ]; then
	if ! which wormhole >/dev/null; then
		if install_apt_package python3-pip; then
			logexec sudo -H pip3 install --upgrade pip
		fi
		install_apt_packages build-essential python3-dev libffi-dev libssl-dev
		logexec sudo -H pip3 install magic-wormhole
	fi
fi

if [ -n "$user_opts" ] && [ -n "$users" ] ; then
	if [ -n "$debug" ]; then
		user_opts="--debug ${user_opts}"
	fi
	if [ -n "$log" ]; then
		user_opts="--log ${log} ${user_opts}"
	fi
	pushd "$DIR"
	bash -x ./prepare_ubuntu_user.sh ${users[0]} ${user_opts} ${private_key_path}
	for user in ${users[@]:1}; do
		bash -x ./prepare_ubuntu_user.sh ${user} ${user_opts}
	done
	popd

fi
