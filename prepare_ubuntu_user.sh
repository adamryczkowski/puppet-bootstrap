#!/bin/bash
cd "$(dirname "$0")" || exit 1
. ./common.sh


usage="
Sets up a new user (if it doesn't exist) and sets some basic properties.
The script must be run as a root.



Usage:

$(basename "$0") <user-name> [--private-key-path <path to the private key>] [--external-key <cipher> <key> <name>]
                        [--help] [--debug] [--log <output file>

where

 --private_key_path       - Path to the file with the ssh private key. 
                            If set, installs private key on the user's 
                            account in the container.
 --no-sudo-password       - If set, sudo will not ask for password
 --external-key           - Sets external public key to access the account. It
    <cipher> <key> <name>   populates authorized_keys
 --repo-path              - Path to the common repository
 --debug                  - Flag that sets debugging mode. 
 --log                    - Path to the log file that will log all meaningful commands
 --bat                    - cat replacement (bat)
 --wormhole               - Magic wormhole
 --dtrx                   - Do The Right Extraction
 --gitutils               - Git utilities: k3diff, meld, difftastic, delta
 --zoxide                 - zoxide (cd replacement)
 --fzf                    - fzf (for bash ctr+r)
 --diff                   - diff-so-fancy (diff),
 --find                   - fd (replaces find)
 --du                     - ncdu (replaces du), 
 --liquidprompt           - liquidprompt
 --git-extra              - git extra (https://github.com/unixorn/git-extra-commands)
 --byobu                  - byobu
 --autojump               - autojump (cd replacement)


Example:

$(basename "$0") adam --private-key-path /tmp/id_rsa --external-key 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKw6Iu/QmWP0Qb5vHDK+dj7eFEPxhEl2x2JuE/t5D0PV adam@adam-gs40'
"

install_bat=0
install_ping=0
install_fzf=0
#install_du=0
install_git_extra=0
install_liquidprompt=0
install_wormhole=0
install_dtrx=0
install_gitutils=0
install_zoxide=0

dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	pwd -P # output full, link-resolved path
}
mypath=${0%/*}
mypath=$(dir_resolve "$mypath")
cd "$mypath" || exit 1


user=$1
if [ -z "$user" ]; then
	echo "$usage"
	exit 0
fi

shift
debug=0
repo_path=""
no_sudo_passwd=0
external_key=""

while [[ $# -gt 0 ]]
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
	# shellcheck disable=SC2034
	repo_path="$1"
	shift
	;;
	--external-key)
	external_key="$1 $2 $3"
	shift
	shift
	shift
	;;
	--no-sudo-password)
	no_sudo_passwd=1
	;;
	--private_key_path)
	# shellcheck disable=SC2034
	private_key_path=$1
	shift
	;;
	--bat)
	install_bat=1
	;;
	--ping)
	install_ping=1
	;;
	--gping)
	install_gping=1
	;;
	--wormhole)
	install_wormhole=1
	;;
	--dtrx)
	install_dtrx=1
	;;
	--gitutils)
	install_gitutils=1
	;;
	--zoxide)
	install_zoxide=1
	;;
	--fzf)
	install_fzf=1
	;;
#	--du)
#	install_du=1
#	;;
	--git-extra)
	install_git_extra=1
	;;
	--liquidprompt)
	install_liquidprompt=1
	;;
	-*)
	echo "Error: Unknown option: $1" >&2
	echo "$usage" >&2
	;;
esac
done

if [ -n "$debug" ]; then
	if [ -z "$log" ]; then
		log=/dev/stdout
	fi
fi

if [ -z "$user" ]; then
  exit 1
fi

if ! grep -q "${user}:" /etc/passwd; then
  sudo adduser --quiet "$user" --disabled-password --add_extra_groups --gecos ''
fi
sshhome=$(getent passwd "$user" | awk -F: '{ print $6 }')

if ! groups "$user" | grep -q "sudo" ; then
  logexec sudo usermod -a -G sudo "$user"
fi
if [ ! -d "${sshhome}/.ssh" ]; then
  logexec sudo mkdir "${sshhome}/.ssh"
  if [[ "$user" != "root" ]]; then
    logexec sudo chown "${user}:${user}" "$sshhome/.ssh"
  fi
fi
if [ -n "$external_key" ]; then
  if ! sudo [ -f "${sshhome}/.ssh/authorized_keys" ]; then
    loglog
    echo "${external_key}" | sudo tee "${sshhome}/.ssh/authorized_keys"
    logexec sudo chmod 0600 "${sshhome}/.ssh/authorized_keys"
    logexec sudo chmod 0700 "${sshhome}/.ssh"
    if [[ "$user" != "root" ]]; then
      logexec sudo chown "${user}:${user}" -R "${sshhome}/.ssh"
    fi
  else
    if ! sudo grep -q "${external_key}" "${sshhome}/.ssh/authorized_keys"; then
      loglog
      echo "${external_key}" >>"${sshhome}/.ssh/authorized_keys"
    fi
  fi
fi

 if [[ "${no_sudo_passwd}" == 1 ]]; then
   if ! sudo [ -f "/etc/sudoers.d/${user}_nopasswd" ]; then
     loglog
     echo "${user} ALL=(ALL) NOPASSWD:ALL" | sudo tee "/etc/sudoers.d/${user}_nopasswd"
   fi
 fi

if sudo [ ! -f "$sshhome/.ssh/id_ed25519.pub" ]; then
  if [ -f "$sshhome/.ssh/id_ed25519" ]; then
    errcho "Abnormal condition: private key is installed without the corresponding public key. Please make sure both files are present, or neither of them. Exiting."
    exit 1
  fi
  tmpfile=$(mktemp -u)
  if ! ssh-keygen -q -t ed25519 -N "" -a 100 -f "$tmpfile"; then
    errcho "Failed to generate SSH key. Exiting."
    exit 1
  fi
  logexec sudo mv "$tmpfile"  "$sshhome/.ssh/id_ed25519"
  logexec sudo mv "${tmpfile}.pub"  "$sshhome/.ssh/id_ed25519.pub"
  if [[ "$user" != "root" ]]; then
    logexec sudo chown "${user}:${user}" "$sshhome/.ssh/id_ed25519"
    logexec sudo chown "${user}:${user}" "$sshhome/.ssh/id_ed25519.pub"
  fi
fi

# shellcheck disable=SC2016
add_bashrc_line 'mkcdir() { mkdir -p -- "$1" && cd -P -- "$1"; }' 30 "mkcdir function"
#linetextfile "${sshhome}/.bashrc" 'mkcdir() { mkdir -p -- "$1" && cd -P -- "$1"; }'

if [ "${install_bat}" == "1" ]; then
#		tmp=$(mktemp)
#		textfile $tmp "#!/bin/bash
#less --tabs 4 -RF \"$@\"" $USER
#		install_script $tmp ${sshhome}/bin/less $user
  install_rust_app bat
  add_bashrc_line 'alias cat="bat"' 30 "cat replacement"
#  linetextfile "${sshhome}/.bashrc" 'alias cat="bat"'
fi

if [ "${install_ping}" == "1" ]; then
  add_bashrc_line 'alias ping="prettyping --nolegend"' 30 "Pretty-ping alias"
#  linetextfile ${sshhome}/.bashrc 'alias ping="prettyping --nolegend"'
fi

if [ "${install_fzf}" == "1" ]; then
  if [ "$install_atuin" == "1" ]; then
    errcho "fzf cannot be installed with atuin. Please install fzf manually."
  fi
  install_rust_app fzf
  add_bashrc_line "alias preview=\"fzf --preview 'bat --color \\\"always\\\" {}'\"" 30 "fzf preview"
  add_bashrc_line "[ -f \"${XDG_CONFIG_HOME:-$HOME/.config}\"/fzf/fzf.bash ] && source \"${XDG_CONFIG_HOME:-$HOME/.config}\"/fzf/fzf.bash" 30 "fzf bash completion"
#  linetextfile ${sshhome}/.bashrc "alias preview=\"fzf --preview 'bat --color \\\"always\\\" {}'\""
#  linetextfile ${sshhome}/.bashrc "[ -f \"${XDG_CONFIG_HOME:-$HOME/.config}\"/fzf/fzf.bash ] && source \"${XDG_CONFIG_HOME:-$HOME/.config}\"/fzf/fzf.bash"
fi

if [ "$install_gitutils" == "1" ]; then
  git config --global init.defaultBranch main

  install_rust_app git-delta
  git config --global core.pager 'delta --diff-so-fancy | less --tabs=4 -RFX'
  git config --global alias.lg 'log --color --graph --pretty=format:'"'"'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset'"'"' --abbrev-commit'

#  git config --global interactive.diffFilter 'delta --color-only'
#  git config --global delta.navigate true
#  git config --global merge.conflictStyle zdiff3

  install_rust_app difftastic
  git config --global diff.external difft
  git config --global difftool.prompt false
  # shellcheck disable=SC2016
  git config --global difftool.difft.cmd 'difft --override='"'"'*.xsd:xml'"'"' "$LOCAL" "$REMOTE"'

  git config --global alias.difft 'git diff --color-words --word-diff-regex='"'"'[^[:space:]]+'"'"' --word-diff "$@"'

  install_apt_package k3diff
  git config --global alias.k3diff '!f() { k3diff "$@" && git difftool --tool=meld "$@"; }; f'
fi

#if [ "${install_diff}" == "1" ]; then
#  if which git 2>/dev/null; then
#    git config --global core.pager "diff-so-fancy | less --tabs=4 -RFX"
#    git config --global color.ui true
#
#    git config --global color.diff-highlight.oldNormal    "red bold"
#    git config --global color.diff-highlight.oldHighlight "red bold 52"
#    git config --global color.diff-highlight.newNormal    "green bold"
#    git config --global color.diff-highlight.newHighlight "green bold 22"
#
#    git config --global color.diff.meta       "yellow"
#    git config --global color.diff.frag       "magenta bold"
#    git config --global color.diff.commit     "yellow bold"
#    git config --global color.diff.old        "red bold"
#    git config --global color.diff.new        "green bold"
#    git config --global color.diff.whitespace "red reverse"
#  fi
#fi
# set -x
#if [ "${install_du}" == "1" ]; then
#  linetextfile ${sshhome}/.bashrc 'alias du="ncdu --color dark -rr -x --exclude .git --exclude node_modules"'
#fi
#set +x

if [ "${install_git_extra}" == "1" ]; then
  add_path_to_bashrc /usr/local/lib/git-extra-commands/bin "git-extra"
#  linetextfile ${sshhome}/.bashrc 'export PATH="$PATH:/usr/local/lib/git-extra-commands/bin"'
fi

if [ "${install_ping}" == "1" ]; then
  add_bashrc_line 'alias ping="prettyping"' "Pretty-ping alias"
#  linetextfile ${sshhome}/.bashrc 'alias ping="prettyping"'
fi

if [ "$install_gping" == "1" ]; then
  install_rust_app gping
#  linetextfile ${sshhome}/.bashrc 'alias ping="gping"'
fi

if [ "$install_wormhole" == "1" ]; then
  install_pipx_command magic-wormhole
#  linetextfile ${sshhome}/.bashrc 'alias wormhole="wormhole send --secure --text"'
fi

if [ "${install_dtrx}" == "1" ]; then
  install_pipx_command dtrx
fi

if [ "${install_zoxide}" == "1" ]; then
  install_rust_app zoxide
  # shellcheck disable=SC2016
  add_bashrc_line 'eval "$(zoxide init bash --cmd cd)"' "Enables Zoxide as 'cd' replacement"
fi

if [ "${install_liquidprompt}" == "1" ]; then
  if [[ "$user" != "$USER" ]]; then
    logexec sudo -Hu "$user" liquidprompt_activate
  else
    logexec liquidprompt_activate
  fi
  install_bash_preexec
  # shellcheck disable=SC2016
  add_bashrc_line 'eval "$(Liquidprompt)"' 91 "Enables Liquidprompt" "$user"
fi

