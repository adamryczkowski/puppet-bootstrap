#!/bin/bash

# TODO: Add scripts that manage the bashrc file using .bashrc.d/ folder

function add_bashrcd_driver {
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
    CONFS=$(ls "${BASHCONFD}"/*.conf 2> /dev/null)
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

function add_bashrc_file {
  local content_filename="$1"
  local filename="$2"
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
  if [[ ! "$filename" =~ $pattern ]]; then
    filename="${filename}.sh"
  fi

  install_file "$content_filename" "$bashrcd/$filename" "$user"
  set_non_executable "$bashrcd/$filename"
}

function add_bashrc_lines {
  local lines="$1"
  local filename="$2"
  local user
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
  if [[ ! "$filename" =~ $pattern ]]; then
    filename="${filename}.sh"
  fi

  textfile "$bashrcd/$filename.sh" "$lines" "$user"
}

function setup_bash_path_man {
  local user
  local home
  if [[ -z ${1+x} ]]; then
    user="$USER"
  else
    user="$1"
  fi
  add_bashrc_file files/bash.d/00_path.sh "00_path.sh" "$user"
  home="$(get_home_dir "$user")"

  if [ ! -f "$home/.path" ]; then
    textfile "$home/.path" "$home/bin
$home/.local/bin" "$user"
  fi
}
function add_path_to_bashrc {
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

function install_bash_preexec {
  local user
  if [[ -z ${1+x} ]]; then
    user="$USER"
  else
    user="$1"
  fi
  local homedir
  homedir="$(get_home_dir "$user")"
  download_file "$homedir/.bash-preexec.sh" https://raw.githubusercontent.com/rcaloras/bash-preexec/master/bash-preexec.sh
  add_bashrc_line '[[ -f ~/.bash-preexec.sh ]] && source ~/.bash-preexec.sh' 90 "bash-preexec" "$user"
}