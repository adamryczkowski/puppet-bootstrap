#!/bin/bash


function replace_bashrc() {
	# Raplaces the bashrc file with the contents of the universal bashrc file
	local bashrc_bak
	local bashrc_src="files/bashrc"
	if [[ -z ${1+x} ]]; then
		user="$USER"
	else
		user="$1"
	fi
	bashrc_bak="$(get_home_dir "$user")/.bashrc.bak"
	if [ ! -f "$bashrc_src" ]; then
		errcho "Cannot find bashrc file $bashrc_src"
		return 1
	fi

	# Compare existing bashrc with the universal bashrc. If they are the same, do nothing.
  if cmp -s "$bashrc_src" "$(get_home_dir "$user")/.bashrc"; then
    return 0
  fi
	if ! [ -f "$(get_home_dir "$user")/.bashrc" ]; then
		install_file "$bashrc_src" "$(get_home_dir "$user")/.bashrc" "$user"
	elif ! cmp -s "$bashrc_src" "$(get_home_dir "$user")/.bashrc"; then
		if [ -f "$bashrc_bak" ]; then
			errcho "Cannot backup .bashrc file to $bashrc_bak, it already exists"
			return 1
		fi
		logexec mv "$(get_home_dir "$user")/.bashrc" "$bashrc_bak"
		install_file "$bashrc_src" "$(get_home_dir "$user")/.bashrc" "$user"
	fi
	setup_bash_path_man "$user"
	add_path_to_bashrc "$HOME/.local/bin" "$user"
	add_bashrc_file files/bashrc.d/01_histcontrol.sh "01_histcontrol.sh" "$user"
	add_bashrc_file files/bashrc.d/02_checkwinsize.sh "02_checkwinsize.sh" "$user"
	add_bashrc_file files/bashrc.d/03_lesspipe.sh "03_lesspipe.sh" "$user"
	add_bashrc_file files/bashrc.d/04_standard_prompt.sh "04_standard_prompt.sh" "$user"
	add_bashrc_file files/bashrc.d/10_color_aliases.sh "10_color_aliases.sh" "$user"
	add_bashrc_file files/bashrc.d/20_bash_aliases.sh "20_bash_aliases.sh" "$user"
	add_bashrc_file files/bashrc.d/30_bash_completions.sh "30_bash_completions.sh" "$user"
}

function add_bashrcd_driver() {
	local user
	local bashrc
	local bashrcd
	if [[ -z ${1+x} ]]; then
		user="$USER"
	else
		user="$1"
	fi
	bashrc="$(get_home_dir "$user")/.bashrc"
	bashrcd="$(get_home_dir "$user")/.bashrc.d"
	if [ ! -d "$bashrcd" ]; then
		logmkdir "$bashrcd" "$user"
	fi
	if [ ! -f "$bashrc" ]; then
		errcho "Cannot find bashrc file $bashrc"
		return 1
	fi
	bash_contents=$(cat <<'EOF'
export BASHCONFD="$HOME/.bashrc.d"

# Source the configurations in .bashrc.d directory
if [ -d "${BASHCONFD}" ]; then
    CONFS=()
    CONFS=$(ls "${BASHCONFD}"/*.sh 2> /dev/null)
    if [ $? -eq 0 ]; then
        for CONF in ${CONFS[@]}
        do
            source $CONF
        done
    fi
    unset CONFS
    unset CONF
fi
EOF
	)
	multilinetextfile "$bashrc" "bash_contents"
}

function add_bashrc_file() {
	local content_filename="$1"
	local bashrc_filename="$2"
	local user
	# Makes a file in ~/.bashrc.d/ with the name of the file, and contents copied from the content_filename
	if [[ -z ${3+x} ]]; then
		user="$USER"
	else
		user="$3"
	fi
	local bashrcd
	bashrcd="$(get_home_dir "$user")/.bashrc.d"
	add_bashrcd_driver "$user"

	# Check if filename already ends in '.sh'. If not - add it
	local pattern='^.*\.sh$'
	if [[ ! "$bashrc_filename" =~ $pattern ]]; then
		bashrc_filename="${bashrc_filename}.sh"
	fi

	install_file "$content_filename" "$bashrcd/$bashrc_filename" "$user"
	set_non_executable "$bashrcd/$bashrc_filename"
}


function add_bashrc_lines() {
	local lines
	local bashrc_filename
#	local user
	lines="$1"
	bashrc_filename="$2"
	# Makes a file in ~/.bashrc.d/ with the name of the file, and contents of the lines
	if [[ -z ${3+x} ]]; then
		user="$USER"
	else
		user="$3"
	fi
	local bashrcd
	bashrcd="$(get_home_dir "$user")/.bashrc.d"
	add_bashrcd_driver "$user"

	# Check if filename already ends in '.sh'. If not - add it
	local pattern='^.*\.sh$'
	if [[ ! "$bashrc_filename" =~ $pattern ]]; then
		bashrc_filename="${bashrc_filename}.sh"
	fi

	textfile "$bashrcd/$bashrc_filename" "$lines" "$user"
}

function setup_bash_path_man() {
	local user
	local home
	if [[ -z ${1+x} ]]; then
		user="$USER"
	else
		user="$1"
	fi
	add_bashrc_file files/bashrc.d/00_path.sh "00_path.sh" "$user"
	home="$(get_home_dir "$user")"

	if [ ! -f "$home/.path" ]; then
		textfile "$home/.path" "$home/bin
		$home/.local/bin" "$user"
	fi
}
function add_path_to_bashrc() {
	local path="$1"
	local user

	if [[ -z ${2+x} ]]; then
		user="$USER"
	else
		user="$2"
	fi
	setup_bash_path_man "$user"
	linetextfile "$(get_home_dir "$user")/.path" "$path"
}

function install_bash_preexec() {
	local user
	if [[ -z ${1+x} ]]; then
		user="$USER"
	else
		user="$1"
	fi
	local homedir
	homedir="$(get_home_dir "$user")"
	download_file "$homedir/.bash-preexec.sh" https://raw.githubusercontent.com/rcaloras/bash-preexec/master/bash-preexec.sh
	add_bashrc_lines '[[ -f ~/.bash-preexec.sh ]] && source ~/.bash-preexec.sh' "80_bash-preexec"
}
