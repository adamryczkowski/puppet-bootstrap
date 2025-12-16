#!/bin/bash
## dependency: prepare_ubuntu_user.sh
## dependency: files/bashrc.d
set -euo pipefail
cd "$(dirname "$0")" || exit 1
. ./common.sh

usage="
Enhances bare-bones Ubuntu installation with several tricks.
It adds a new user,
fixes locale,
installs byobu, htop and mcedit

The script must be run as a root.

Usage:

$(basename "$0") <user-name> [--apt-proxy IP:PORT] [--wormhole] [--need-apt-update]

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
--rust                   - Use Rust's cargo to install all the rust packages
--pipx                   - Use pipx to install all the python packages
--cli-improved           - Install all the following recommended command line tools:
--bat                    - cat replacement (bat)
--bashrcd                - Replace existing .bashrc with a new one. Old bashrc will be backed up.
--ping                   - prettyping (ping),
--eza                    - eza (ls replacement),
--gping						      - gping (https://github.com/orf/gping)
--fzf                    - fzf (for bash ctr+r)
--atuin                  - atuin (command history replacement)
--gitutils               - Git utilities: k3diff, meld, difftastic, delta
--htop                   - htop
--btop                   - btop
--difft                  - difftastic (diff replacement)
--find                   - fd (replaces find)
--du                     - ncdu (replaces du),
--bandwidth              - bandwidth (Terminal bandwidth utilization tool),
--tldr                   - tldr
--rg                     - ripgrep,
--entr                   - entr (watch),
--dust                   - non-interactive replacement to du
--aptitude               - aptitude
--mc                     - mc (Midnight Commander)
--git-extra              - git extra (https://github.com/unixorn/git-extra-commands)
--liquidprompt           - liquidprompt
--byobu                  - byobu
--hexyl                  - hexyl (a hex editor)
--zoxide                 - zoxide (cd replacement)
--dtrx                   - Do The Right eXtraction (untar/unzip/unrar/etc. replacement)

Example:

$(basename "$0") --apt-proxy 192.168.10.2:3142
"

dir_resolve() {
  cd "$1" 2>/dev/null || return $? # cd to desired directory; if fail, quell any error messages but return exit status
  pwd -P                           # output full, link-resolved path
}
mypath=${0%/*}
mypath=$(dir_resolve "$mypath")
cd "$mypath" || exit 1

users=()
pattern='^--.*$'
# If the first argument is a username (not an option), treat it as the primary user
if [[ -n "${1:-}" && ! "${1:-}" =~ $pattern ]]; then
  users+=("$1")
  shift
fi

private_key_path=""
debug=0
repo_path=""
aptproxy=""
install_rust=0
install_wormhole=0
install_pipx=0
install_bat=0
install_bashrcd=0
install_ping=0
install_gping=0
install_fzf=0
install_atuin=0
install_htop=0
install_difft=0
install_find=0
install_eza=0
install_du=0
install_bandwidth=0
install_tldr=0
install_rg=0
install_entr=0
install_dust=0
install_aptitude=0
install_mc=0
#install_git_extra=0
install_liquidprompt=0
install_byobu=0
install_hexyl=0
install_dtrx=0
install_btop=0
install_gitutils=0
install_zoxide=0

user_opts=""

while [[ $# -gt 0 ]]; do
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
    # shellcheck disable=SC2034
    repo_path="$1"
    shift
    ;;
  --apt-proxy)
    aptproxy=$1
    shift
    ;;
  --no-sudo-password)
    user_opts="${user_opts:-} --no-sudo-password"
    ;;
  --external-key)
    user_opts="${user_opts:-} --external-key $1 $2 $3"
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
  --user)
    users+=("$1")
    shift
    ;;
  --wormhole)
    # shellcheck disable=SC2034
    install_wormhole=1
    ;;
  --rust)
    install_rust=1
    ;;
  --pipx)
    install_pipx=1
    ;;
  --need-apt-update)
    flag_need_apt_update=1
    ;;
  --cli-improved)
    install_bat=1
    install_bashrcd=1
    install_btop=1
    install_zoxide=1
    install_ping=1
    install_gping=0 # TODO
    install_htop=1
    install_atuin=1
    install_eza=1
    install_difft=1
    install_find=1
    install_du=1
    install_tldr=1
    install_rg=1
    install_bandwidth=1
    install_entr=1
    install_dust=1
    install_mc=1
    install_dtrx=1
    install_aptitude=1
    install_wormhole=1
    install_liquidprompt=1
    install_byobu=1
    install_hexyl=1
    ;;
  --bat)
    # shellcheck disable=SC2034
    install_bat=1
    ;;
  --bashrcd)
    # shellcheck disable=SC2034
    install_bashrcd=1
    ;;
  --btop)
    # shellcheck disable=SC2034
    install_btop=1
    ;;
  --gitutils)
    # shellcheck disable=SC2034
    install_gitutils=1
    ;;
  --eza)
    install_eza=1
    ;;
  --zoxide)
    # shellcheck disable=SC2034
    install_zoxide=1
    ;;
  --ping)
    install_ping=1
    ;;
  --gping)
    install_gping=1
    ;;
  --fzf)
    install_fzf=1
    ;;
  --htop)
    install_htop=1
    ;;
  --difft)
    install_difft=1
    ;;
  --find)
    install_find=1
    ;;
  --du)
    install_du=1
    ;;
  --bandwidth)
    install_bandwidth=1
    ;;
  --tldr)
    install_tldr=1
    ;;
  --rg)
    install_rg=1
    ;;
  --entr)
    install_entr=1
    ;;
  --dust)
    install_dust=1
    ;;
  --mc)
    install_mc=1
    ;;
  --aptitude)
    install_aptitude=1
    #	;;
    #	--git-extra)
    #	install_git_extra=1
    #	user_opts="${user_opts} --git-extra"
    ;;
  --liquidprompt)
    install_liquidprompt=1
    ;;
  --byobu)
    install_byobu=1
    ;;
  --hexyl)
    install_hexyl=1
    ;;
  --dtrx)
    install_dtrx=1
    ;;
  -*)
<<<<<<< Updated upstream
    echo "Error: Unknown option: ${1:-}" >&2
=======
    echo "Error: Unknown option: $key" >&2
>>>>>>> Stashed changes
    echo "$usage" >&2
    ;;
  esac
done

if [ ${#users[@]} -eq 0 ]; then
  users+=("$USER")
fi

if [ -n "$debug" ]; then
  if [ -z "$log" ]; then
    log=/dev/stdout
  fi
fi

<<<<<<< Updated upstream
check_for_root;
=======
if ! check_for_root; then
  exit 1
fi
>>>>>>> Stashed changes

install_apt_package wget wget
install_apt_package jq jq

if [ -n "$aptproxy" ]; then
  # shellcheck disable=SC2090
  $loglog
  echo "Acquire::http::Proxy \"http://$aptproxy\";" | sudo tee /etc/apt/apt.conf.d/90apt-cacher-ng >/dev/null
  # shellcheck disable=SC2034
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

#if [ "${install_bat}" == "1" ]; then
#	version=$(get_latest_github_release_name sharkdp/bat skip_v)
#
#	link=$(get_latest_github_release_link sharkdp/bat bat_${version}_$(cpu_arch).deb bat_${version}_$(cpu_arch).deb )
#	install_apt_package_file bat_${version}_$(cpu_arch).deb bat $link
#fi

if [ "${install_bashrcd}" == "1" ]; then
  user_opts="${user_opts} --bashrcd"
fi

if [ "${install_gitutils}" == "1" ]; then
  install_rust=1
  install_difft=1
  user_opts="${user_opts} --gitutils"
fi

if [ "${install_bat}" == "1" ]; then
  install_rust=1
  user_opts="${user_opts} --bat"
fi

if [ "${install_zoxide}" == "1" ]; then
  install_rust=1
  user_opts="${user_opts} --zoxide"
fi

if [ "${install_atuin}" == "1" ]; then
  install_rust=1
  user_opts="${user_opts} --atuin"
fi

if [ "${install_rust}" == "1" ]; then
  install_rust
fi

if [ "${install_pipx}" == "1" ]; then
  install_pipx
fi

if [ "${install_ping}" == "1" ]; then
  install_apt_package prettyping
  user_opts="${user_opts} --ping"

#	plik=$(get_cached_file prettyping https://raw.githubusercontent.com/denilsonsa/prettyping/master/prettyping)
#	install_script "${plik}" /usr/local/bin/prettyping root
fi

if [ "${install_gping}" == "1" ]; then
  if [ "${install_rust}" == "0" ]; then
    add_apt_source_manual gping "deb http://packages.azlux.fr/debian/ buster main" https://azlux.fr/repo.gpg.key gping.gpg.key
    install_apt_packages gping
  fi
  user_opts="${user_opts} --gping"
fi

if [ "${install_fzf}" == "1" ]; then
  user_opts="${user_opts} --fzf"
  if [ "${install_pipx}" == "0" ]; then
    install_apt_package fzf
  fi
#		get_git_repo https://github.com/junegunn/fzf.git /usr/local/lib
#		logexec sudo /usr/local/lib/fzf/install --all --xdg
fi

if [ "${install_htop}" == "1" ]; then
  install_apt_package htop
fi

if [ "${install_btop}" == "1" ]; then
  install_apt_package btop
  user_opts="${user_opts} --btop"
fi

if [ "${install_dtrx}" == "1" ]; then
  if [ "${install_pipx}" == "0" ]; then
    install_apt_package dtrx
  else
    user_opts="${user_opts} --dtrx"
  fi
#	if ! install_apt_package dtrx; then
#		install_pip3_packages dtrx
#	fi
fi

if [ "${install_difft}" == "1" ]; then
  if [ "${install_rust}" == "0" ]; then
    install_gh_binary Wilfred/difftastic /usr/local/share difft
  else
    user_opts="${user_opts} --difft"
  fi
#    install_rust # The only way to install difftastic is via Rust, which will be handled by the script
#	plik=$(get_cached_file diff-so-fancy https://raw.githubusercontent.com/so-fancy/diff-so-fancy/master/third_party/build_fatpack/diff-so-fancy)
#	install_script "${plik}" /usr/local/bin/diff-so-fancy
fi

if [ "${install_eza}" == "1" ]; then
  if [ "${install_rust}" == "0" ]; then
    install_apt_package eza
  fi
  user_opts="${user_opts} --eza"
  if command -v fc-list >/dev/null 2>&1; then
    if ! fc-list | grep -Fq "FiraCode Nerd Font Med"; then
      download_file "/tmp/FiraCode.tar.xz" "$(get_gh_download_link "ryanoasis/nerd-fonts" "FiraCode.tar.xz")"
      extract_archive "/tmp/FiraCode.tar.xz" "/usr/local/share/fonts" "root" "rename" "FiraCode"
      logexec sudo fc-cache -f
    fi
  fi
fi

if [ "${install_find}" == "1" ]; then
  if [ "${install_rust}" == "0" ]; then
    install_apt_package fd-find
  else
    user_opts="${user_opts} --find"
  fi
#	fd_arch=$(cpu_arch)
#	if [ "${fd_arch}" == "arm64" ]; then
#		fd_arch="armhf"
#	fi
#	file="fd_$(get_latest_github_release_name sharkdp/fd skip_v)_$(cpu_arch).deb"
#	link=$(get_latest_github_release_link sharkdp/fd ${file} ${file})
#	install_apt_package_file ${file} fd $link
fi
if [ "${install_du}" == "1" ]; then
  install_apt_package ncdu
  user_opts="${user_opts} --du"

#	cached_file=$(get_cached_file ncdu.tar.gz https://dev.yorhel.nl/download/ncdu-1.14.tar.gz)
#	tmp=$(mktemp -d)
#	# shellcheck disable=SC2034
#	skip_timestamp=1
#	uncompress_cached_file ${cached_file} $tmp
#	install_apt_packages build-essential libncurses5-dev
#	logexec pushd ${tmp}/ncdu
#	logexec ./configure
#	logexec make
#	logexec sudo make install
#	logexec popd
fi
if [ "${install_bandwidth}" == "1" ]; then
  if [ "${install_rust}" == "0" ]; then
    install_gh_binary imsnif/bandwhich /usr/local/share bandwhich
  else
    user_opts="${user_opts} --bandwidth"
  fi

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
  if [ "${install_rust}" == "0" ]; then
    install_gh_binary bootandy/dust /usr/local/share dust
  else
    user_opts="${user_opts} --dust"
  fi
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
  if [ "${install_pipx}" == "0" ]; then
    install_apt_packages tldr-py
  else
    user_opts="${user_opts} --tldr"
  fi
fi

if [ "${install_rg}" == "1" ]; then
  if [ "${install_rust}" == "0" ]; then
    if ! install_apt_packages ripgrep; then
      install_gh_binary BurntSushi/ripgrep /usr/local/share rg "" "" "" "" rg
    fi
  else
    user_opts="${user_opts} --rg"
  fi
#	install_gh_deb BurntSushi/ripgrep ripgrep
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
  install_apt_package entr
#	get_cached_file entr-4.2.tar.gz http://entrproject.org/code/entr-4.2.tar.gz
#	tmp=$(mktemp -d)
#	pushd $tmp
#	uncompress_cached_file entr-4.2.tar.gz eradman
#	logexec cd eradman
#	install_apt_packages build-essential
#	logexec ./configure
#	logexec make
#	logexec sudo make install
#	logexec popd
fi

if [ "${install_mc}" == "1" ]; then
  install_apt_package mc
fi

if [ "${install_aptitude}" == "1" ]; then
  install_apt_package aptitude
fi

#if [ "${install_git_extra}" == "1" ]; then
#	get_git_repo https://github.com/unixorn/git-extra-commands.git /usr/local/lib git-extra-commands
#fi

if [ "${install_liquidprompt}" == "1" ]; then
  install_apt_packages liquidprompt
  logexec sudo -H liquidprompt_activate
  user_opts="${user_opts} --liquidprompt"
fi

if [ "${install_byobu}" == "1" ]; then
  install_apt_package byobu
fi

if [ "${install_hexyl}" == "1" ]; then
  if [ "${install_rust}" == "0" ]; then
    install_apt_package hexyl
  else
    user_opts="${user_opts} --hexyl"
  fi
#	install_gh_deb sharkdp/hexyl hexyl
fi

if [ "${install_wormhole}" == "1" ]; then
  if [ "${install_pipx}" == "0" ]; then
    install_apt_package magic-wormhole
  else
    user_opts="${user_opts} --wormhole"
  fi
fi
set -x
# shellcheck disable=SC2128
if [ "${#users[@]}" -gt 0 ]; then
  if [ -n "$debug" ]; then
    user_opts="--debug ${user_opts}"
  fi
  if [ -n "$log" ]; then
    user_opts="--log ${log} ${user_opts}"
  fi
  pushd "$DIR" || exit 1
  #	set -x
<<<<<<< Updated upstream
  # shellcheck disable=SC2086
  echo ./prepare_ubuntu_user.sh "${users[0]}" ${user_opts} ${private_key_path}
  # shellcheck disable=SC2086
  bash -x ./prepare_ubuntu_user.sh "${users[0]}" ${user_opts} ${private_key_path}
=======
  echo ./prepare_ubuntu_user.sh ${users[0]} ${user_opts} ${private_key_path:-}
  bash -x ./prepare_ubuntu_user.sh ${users[0]} ${user_opts} ${private_key_path:-}
>>>>>>> Stashed changes
  for user in "${users[@]:1}"; do
    # shellcheck disable=SC2086
    sudo -H -u "${user}" -- bash -x ./prepare_ubuntu_user.sh "${user}" ${user_opts}
  done
  popd || exit 1
fi
