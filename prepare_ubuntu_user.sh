#!/bin/bash
cd `dirname $0`
. ./common.sh


usage="
Sets up a new user (if it doesn't exist) and sets some basic properties.
The script must be run as a root.



Usage:

$(basename $0) <user-name> [--private-key-path <path to the private key>] [--external-key <cipher> <key> <name>]
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
 --fzf                    - fzf (for bash ctr+r)
 --diff                   - diff-so-fancy (diff),
 --find                   - fd (replaces find)
 --du                     - ncdu (replaces du), 
 --liquidprompt           - liquidprompt
 --git-extra              - git extra (https://github.com/unixorn/git-extra-commands)
 --byobu                  - byobu
 --autojump               - autojump (cd replacement)


Example:

$(basename $0) adam --private-key-path /tmp/id_rsa --external-key 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKw6Iu/QmWP0Qb5vHDK+dj7eFEPxhEl2x2JuE/t5D0PV adam@adam-gs40'
"

install_bat=0
install_ping=0
install_fzf=0
install_diff=0
install_du=0
install_git_extra=0
install_liquidprompt=0
install_autojump=0

dir_resolve()
{
	cd "$1" 2>/dev/null || return $?  # cd to desired directory; if fail, quell any error messages but return exit status
	echo "`pwd -P`" # output full, link-resolved path
}
mypath=${0%/*}
mypath=`dir_resolve $mypath`
cd $mypath


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
	private_key_path=$1
	shift
	;;
	--bat)
	install_bat=1
	;;
	--ping)
	install_ping=1
	;;
	--fzf)
	install_fzf=1
	;;
	--diff)
	install_diff=1
	;;
	--du)
	install_du=1
	;;
	--git-extra)
	install_git_extra=1
	;;
	--autojump)
	install_autojump=1
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

if [ -n "$user" ]; then
	if ! grep -q "${user}:" /etc/passwd; then
		logexec sudo adduser --quiet $user --disabled-password --add_extra_groups --gecos ''
	fi
	sshhome=$(getent passwd $user | awk -F: '{ print $6 }')
        
	if ! groups $user | grep -q "sudo" ; then      
		logexec sudo usermod -a -G sudo $user
	fi
	if [ ! -d ${sshhome}/.ssh ]; then
		logexec sudo mkdir ${sshhome}/.ssh
		if [[ "$user" != "root" ]]; then
			logexec sudo chown ${user}:${user} "$sshhome/.ssh"
		fi
	fi
   set -x
	if [ -n "$external_key" ]; then
		if ! sudo [ -f ${sshhome}/.ssh/authorized_keys ]; then
			loglog
			echo "${external_key}" | sudo tee ${sshhome}/.ssh/authorized_keys
			logexec sudo chmod 0600 ${sshhome}/.ssh/authorized_keys
			logexec sudo chmod 0700 ${sshhome}/.ssh
			if [[ "$user" != "root" ]]; then
				logexec sudo chown ${user}:${user} -R ${sshhome}/.ssh 
			fi
		else
			if ! sudo grep -q "${external_key}" ${sshhome}/.ssh/authorized_keys; then
				loglog
				echo "${external_key}" >>${sshhome}/.ssh/authorized_keys
			fi
		fi
	fi

   if [[ "${no_sudo_passwd}" == 1 ]]; then
	   if ! sudo [ -f /etc/sudoers.d/${user}_nopasswd ]; then
		   loglog
		   echo "${user} ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/${user}_nopasswd
	   fi
   fi
           
	if sudo [ ! -f "$sshhome/.ssh/id_ed25519.pub" ]; then
		if [ -f "$sshhome/.ssh/id_ed25519" ]; then
			errcho "Abnormal condition: private key is installed without the corresponding public key. Please make sure both files are present, or neither of them. Exiting."
			exit 1
		fi
		tmpfile=$(mktemp)
		logexec ssh-keygen -q -t ed25519 -N "" -a 100 -f "$tmpfile"

		if [ $? -ne 0 ]; then
			exit 1
		fi
		logexec sudo mv "$tmpfile"  "$sshhome/.ssh/id_ed25519"
		logexec sudo mv "${tmpfile}.pub"  "$sshhome/.ssh/id_ed25519.pub"
		if [[ "$user" != "root" ]]; then
			logexec sudo chown ${user}:${user} "$sshhome/.ssh/id_ed25519"
			logexec sudo chown ${user}:${user} "$sshhome/.ssh/id_ed25519.pub"
		fi
	fi
	
	linetextfile ${sshhome}/.bashrc 'mkcdir() { mkdir -p -- "$1" && cd -P -- "$1"; }'
	
	if [ "${install_bat}" == "1" ]; then
#		tmp=$(mktemp)
#		textfile $tmp "#!/bin/bash
#less --tabs 4 -RF \"$@\"" $USER
#		install_script $tmp ${sshhome}/bin/less $user
		linetextfile ${sshhome}/.bashrc 'alias cat="bat"'
	fi
	
	if [ "${install_ping}" == "1" ]; then
		linetextfile ${sshhome}/.bashrc 'alias ping="prettyping --nolegend"'
	fi

	if [ "${install_fzf}" == "1" ]; then
		linetextfile ${sshhome}/.bashrc "alias preview=\"fzf --preview 'bat --color \\\"always\\\" {}'\""
		linetextfile ${sshhome}/.bashrc "[ -f \"${XDG_CONFIG_HOME:-$HOME/.config}\"/fzf/fzf.bash ] && source \"${XDG_CONFIG_HOME:-$HOME/.config}\"/fzf/fzf.bash"
	fi
	
	if [ "${install_diff}" == "1" ]; then
		if which git 2>/dev/null; then
			git config --global core.pager "diff-so-fancy | less --tabs=4 -RFX"
			git config --global color.ui true

			git config --global color.diff-highlight.oldNormal    "red bold"
			git config --global color.diff-highlight.oldHighlight "red bold 52"
			git config --global color.diff-highlight.newNormal    "green bold"
			git config --global color.diff-highlight.newHighlight "green bold 22"

			git config --global color.diff.meta       "yellow"
			git config --global color.diff.frag       "magenta bold"
			git config --global color.diff.commit     "yellow bold"
			git config --global color.diff.old        "red bold"
			git config --global color.diff.new        "green bold"
			git config --global color.diff.whitespace "red reverse"
		fi
	fi
	
	if [ "${install_du}" == "1" ]; then
		linetextfile ${sshhome}/.bashrc 'alias du="ncdu --color dark -rr -x --exclude .git --exclude node_modules"'
	fi
	
	if [ "${install_git_extra}" == "1" ]; then
		linetextfile ${sshhome}/.bashrc 'export PATH="$PATH:/usr/local/lib/git-extra-commands/bin"'
	fi
	
	if [ "${install_ping}" == "1" ]; then
		linetextfile ${sshhome}/.bashrc 'alias ping="prettyping"'
	fi
	
	if [ "${install_autojump}" == "1" ]; then
		if dpkg -s autojump >/dev/null 2>/dev/null; then
			linetextfile ${sshhome}/.bashrc 'source /usr/share/autojump/autojump.sh'
		fi
	fi

	if [ "${install_liquidprompt}" == "1" ]; then
		if dpkg -s liquidprompt >/dev/null 2>/dev/null; then
			if [[ "$user" != "root" ]]; then
				logexec sudo -Hu $user liquidprompt_activate
			else
				logexec liquidprompt_activate
			fi
		fi
	fi

fi

