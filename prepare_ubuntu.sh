#!/bin/bash
## dependency: prepare_ubuntu_user.sh
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
 --external-key           - Sets external public key to access the account. It
    <cipher> <key> <name>   populates authorized_keys
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands
 --repo-path              - Path to the common repository
 --user <username>        - Additional user to install the tricks to. Can be specified
                            multiple times, each time adding another user.
 --no-sudo-password       - If set, sudo will not ask for password
 --cli-improved           - Install all the following recommended command line tools:
 --bat                    - cat replacement (bat)
 --ping                   - prettyping (ping),
 --fzf                    - fzf (for bash ctr+r)
 --htop                   - htop
 --diff                   - diff-so-fancy (diff),
 --find                   - fd (replaces find)
 --du                     - ncdu (replaces du), 
 --bandwidth              - bandwidth (Terminal bandwidth utilization tool), 
 --tldr                   - tldr,
 --ag                     - ag (the silver searcher), 
 --rg                     - ripgrep,
 --entr                   - entr (watch), 
 --noti                   - noti (notification when something is done)
 --dust                   - non-interactive replacement to du
 --aptitude               - aptitude
 --mc                     - mc (Midnight Commander)
 --git-extra              - git extra (https://github.com/unixorn/git-extra-commands)
 --liquidprompt           - liquidprompt
 --byobu                  - byobu
 --hexyl                  - hexyl (a hex editor)
 --autojump               - autojump (cd replacement)
 --dtrx                   - Do The Right eXtraction (untar/unzip/unrar/etc. replacement)

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
install_bandwidth=0
install_tldr=0
install_ag=0
install_rg=0
install_entr=0
install_noti=0
install_dust=0
install_aptitude=0
install_mc=0
install_git_extra=0
install_liquidprompt=0
install_byobu=0
install_hexyl=0
install_autojump=0
install_dtrx=0

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
	--no-sudo-password)
	user_opts="${user_opts} --no-sudo-password $1"
	;;
	--external-key)
	user_opts="${user_opts} --external-key $1 $2 $3"
	shift
	shift
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
	--cli-improved)
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
	install_rg=1
   install_bandwidth=1
	install_entr=1
	install_noti=1
	install_dust=1
	install_mc=1
	install_dtrx=1
	install_aptitude=1
	install_liquidprompt=1
	user_opts="${user_opts} --liquidprompt"
	install_byobu=1
	install_hexyl=1
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
	--bandwidth)
	install_bandwidth=1
	;;
	--tldr)
	install_tldr=1
	;;
	--ag)
	install_ag=1
	;;
	--rg)
	install_rg=1
	;;
	--entr)
	install_entr=1
	;;
	--noti)
	install_noti=1
	;;
	--dust)
	install_dust=1
	;;
	--mc)
	install_mc=1
	;;
	--aptitude)
	install_aptitude=1
	;;
	--git-extra)
	install_git_extra=1
	user_opts="${user_opts} --git-extra"
	;;
	--liquidprompt)
	install_liquidprompt=1
	user_opts="${user_opts} --liquidprompt"
	;;
	--byobu)
	install_byobu=1
	;;
	--hexyl)
	install_hexyl=1
	;;
	--autojump)
	install_autojump=1
	user_opts="${user_opts} --autojump"
	;;
	--dtrx)
	install_dtrx=1
	user_opts="${user_opts} --dtrx"
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

if check_for_root; then
	return 1
fi

install_apt_package wget wget 

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

install_apt_packages bash-completion curl
#	install_byobu=1

if [ "${install_bat}" == "1" ]; then
	version=$(get_latest_github_release_name sharkdp/bat skip_v)
	
	link=$(get_latest_github_release_link sharkdp/bat bat_${version}_$(cpu_arch).deb bat_${version}_$(cpu_arch).deb )
	install_apt_package_file bat_${version}_$(cpu_arch).deb bat $link
fi

if [ "${install_ping}" == "1" ]; then
	plik=$(get_cached_file prettyping https://raw.githubusercontent.com/denilsonsa/prettyping/master/prettyping)
	install_script "${plik}" /usr/local/bin/prettyping root
fi

if [ "${install_fzf}" == "1" ]; then
	if ! install_apt_package fzf; then
		get_git_repo https://github.com/junegunn/fzf.git /usr/local/lib 
		logexec sudo /usr/local/lib/fzf/install --all --xdg
	fi
fi

if [ "${install_htop}" == "1" ]; then
	install_apt_package htop
fi

if [ "${install_dtrx}" == "1" ]; then
	if ! install_apt_package dtrx; then
		install_pip3_packages dtrx
	fi
fi

if [ "${install_diff}" == "1" ]; then
	plik=$(get_cached_file diff-so-fancy https://raw.githubusercontent.com/so-fancy/diff-so-fancy/master/third_party/build_fatpack/diff-so-fancy)
	install_script "${plik}" /usr/local/bin/diff-so-fancy
fi

if [ "${install_find}" == "1" ]; then
	install_gh_deb sharkdp/fd fd
#	fd_arch=$(cpu_arch)
#	if [ "${fd_arch}" == "arm64" ]; then
#		fd_arch="armhf"
#	fi
#	file="fd_$(get_latest_github_release_name sharkdp/fd skip_v)_$(cpu_arch).deb"
#	link=$(get_latest_github_release_link sharkdp/fd ${file} ${file})
#	install_apt_package_file ${file} fd $link
fi
set -x
if [ "${install_du}" == "1" ]; then
	cached_file=$(get_cached_file ncdu.tar.gz https://dev.yorhel.nl/download/ncdu-1.14.tar.gz)
	tmp=$(mktemp -d)
	skip_timestamp=1
	uncompress_cached_file ${cached_file} $tmp 
	install_apt_packages build-essential libncurses5-dev
	logexec pushd ${tmp}/ncdu
	logexec ./configure
	logexec make
	logexec sudo make install
	logexec popd
fi
set +x
if [ "${install_bandwidth}" == "1" ]; then
	install_gh_binary imsnif/bandwhich /usr/local/share bandwhich

#	

#	_arch=$(cpu_arch)
#	if [ "${_arch}" == "amd64" ]; then
#		_arch="x86_64-unknown-linux-musl"
#	fi
#   version=$(get_latest_github_release_name imsnif/bandwhich)
#   file="bandwhich-v${version}-${_arch}.tar.gz"
#	link="https://github.com/imsnif/bandwhich/releases/download/${version}/${file}"
#	filepath=$(get_cached_file ${file} ${link})
#   get_from_cache_and_uncompress_file ${filepath} bandwhich ${link} "/usr/local/bin/bandwhich" root   
fi

if [ "${install_dust}" == "1" ]; then
	install_gh_binary bootandy/dust /usr/local/share dust
#	_arch=$(cpu_arch)
#	if [ "${_arch}" == "amd64" ]; then
#		_arch="x86_64-unknown-linux-gnu"
#	elif [ "${_arch}" == "arm64" ]; then
#		_arch="arm-unknown-linux-gnueabihf"
#	fi
#   version=$(get_latest_github_release_name bootandy/dust)
#	file="dust-${version}-${_arch}.tar.gz"
#	link="https://github.com/bootandy/dust/releases/download/${version}/${file}"
#	filepath=$(get_cached_file ${file} ${link})
#   get_from_cache_and_uncompress_file ${filepath} ${link} "/usr/local/share/dust" root
#	make_symlink /usr/local/share/dust-${version}-x86_64-unknown-linux-gnu/dust /usr/local/bin/dust
fi

if [ "${install_tldr}" == "1" ]; then
	install_apt_packages python3-pip
	install_pip3_packages tldr
fi

if [ "${install_ag}" == "1" ]; then
	install_apt_packages silversearcher-ag
fi

if [ "${install_rg}" == "1" ]; then
	install_gh_deb BurntSushi/ripgrep ripgrep
	if $?; then
		 install_gh_binary BurntSushi/ripgrep /usr/local/share rg "" "" "" "" rg
	fi
#	_arch=$(cpu_arch)
#	if [ "${_arch}" == "arm64" ]; then
#		_arch="arm-unknown-linux-gnueabihf"
#	fi
#   version=$(get_latest_github_release_name BurntSushi/ripgrep)
#	file="ripgrep-${version}-${_arch}.tar.gz"
#	link="https://github.com/BurntSushi/ripgrep/releases/download/${version}/${file}"
#	filepath=$(get_cached_file ${file} ${link})
#   get_from_cache_and_uncompress_file ${filepath} ${link} "/usr/local/share/ripgrep" root
#	make_symlink /usr/local/share/ripgrep/ripgrep /usr/local/bin/ripgrep
#   add_ppa x4121/ripgrep
#   install_apt_packages ripgrep
fi

if [ "${install_entr}" == "1" ]; then
	get_cached_file entr-4.2.tar.gz http://entrproject.org/code/entr-4.2.tar.gz
	tmp=$(mktemp -d)
	pushd $tmp
	uncompress_cached_file entr-4.2.tar.gz eradman
	logexec cd eradman
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

if [ "${install_aptitude}" == "1" ]; then
	install_apt_package aptitude
fi

if [ "${install_git_extra}" == "1" ]; then
	get_git_repo https://github.com/unixorn/git-extra-commands.git /usr/local/lib git-extra-commands
fi

if [ "${install_liquidprompt}" == "1" ]; then
	install_apt_packages liquidprompt
	logexec sudo -H liquidprompt_activate
fi

if [ "${install_byobu}" == "1" ]; then
	install_apt_package byobu
fi

if [ "${install_hexyl}" == "1" ]; then
	install_gh_deb sharkdp/hexyl hexyl
#	file="hexyl_$(get_latest_github_release_name sharkdp/hexyl skip_v)_$(cpu_arch).deb"
#	link=$(get_latest_github_release_link sharkdp/hexyl ${file} ${file})
#	install_apt_package_file ${file} hexyl $link


#	install_apt_package_file fd-musl_7.1.0_amd64.debhexyl_0.3.1_amd64.deb hexyl https://github.com/sharkdp/hexyl/releases/download/v0.3.1/hexyl_0.3.1_amd64.deb
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

if [ -n "$users" ] ; then
	if [ -n "$debug" ]; then
		user_opts="--debug ${user_opts}"
	fi
	if [ -n "$log" ]; then
		user_opts="--log ${log} ${user_opts}"
	fi
	pushd "$DIR"
#	set -x
	bash -x ./prepare_ubuntu_user.sh ${users[0]} ${user_opts} ${private_key_path}
	for user in ${users[@]:1}; do
		sudo -H -u ${user} -- bash -x ./prepare_ubuntu_user.sh ${user} ${user_opts}
	done
	popd
fi
