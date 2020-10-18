#!/bin/bash


cd `dirname $0`
. ./common.sh


usage="
Prepares julia


Usage:

$(basename $0) [--juno|--atom] [--pycall <path_to_python>|auto] [--dev]
               [--deb-folder <deb_folder>] [--install-dir <path>]
                [--help] [--debug] [--log <output file>]


where

 --juno                       - Flag to specify whether to install juno if atom exists. --atom implies --juno.
 --atom                       - Flag to specify whether to install atom (in order to install juno)
 --dev                        - Include development packages: Revise, Rebugger, Debugger, OhMyREPL
 --user								- Username for whom install extra bits, like startup.jl. Defaults to the $USER
 --preload-spack-python-from  - Path with the spack installation directory from which python will be preloaded.
                                Implies --pycall <path to python>
 --pycall <path to python>    - Installs PyCall in julia and sets the python interpreter. Auto sets the interpreter
                                to \`which python\` or installs the python itself if python not found.
 --install-dir <path>         - Place to install julia to. Defaults to /opt/julia
 --debug                      - Flag that sets debugging mode.
 --log                        - Path to the log file that will log all meaningful commands
 --deb-folder <path>          - Path where the source files for julia will be downloaded.
                                Preferably some sort of shared folder for whole institution.

Example2:

$(basename $0) --juno --pycall auto --deb-folder /media/adam-minipc/other/debs --debug

"

if [ -z "$1" ]; then
	echo "$usage" >&2
	exit 0
fi

set -x

use_juno=0
use_atom=0
use_dev=0
which_python=""
spack_python=""
install_dir=/opt/julia

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--juno)
	use_juno=1
	;;
	--atom)
	use_juno=1
	use_atom=1
	;;
	--pycall)
	which_python=$1
	shift
	;;
	--deb-folder)
	repo_path=$1
	shift
	;;
	--install-dir)
	install_dir="$1"
	shift
	;;
	--dev)
	use_dev=1
	;;
	--user)
	user=$1
	shift
	;;
  --preload-spack-python-from)
  spack_python="$1"
  shift
  ;;
	--debug)
	debug=1
	;;
	--log)
	log=$1
	shift
	;;
	--help)
	echo "$usage"
	exit 0
	;;
	-*)
	echo "Error: Unknown option: $1" >&2
	echo "$usage" >&2
	exit 1
	;;
esac
done

if [ -n "$debug" ]; then
	if [ -z "$log" ]; then
		log=/dev/stdout
	fi
fi


if [ -n "$spack_python" ]; then
  if [ -d "${spack_python}" ]; then
    source ${spack_python}/share/spack/setup-env.sh
    spack install python py-setuptools py-pip py-ipython
    spack load py-setuptools
    spack load py-pip
    spack load py-ipython
    spack load python
    which_python=$(which python)
  fi
fi

if [[ "${which_python}" == "auto" ]]; then
  which_python=$(which python 2>/dev/null)
  if [[ ! "$?" == "0" ]]; then
    errcho "Cannot find python. Will install python from distribution."
    if ! install_apt_package python3 python; then
      errcho "Error while installing python. There will be no python in the install"
      exit 1
    fi
    which_python=$(which python 2>/dev/null)
  fi
fi

if [ -n "${which_python}" ]; then
  if ! $(${which_python} --version >/dev/null 2>/dev/null); then
    errcho "Cannot execute python binary in ${which_python}"
    return 1
  fi
fi

julia_version=$(get_latest_github_release_name JuliaLang/julia skip_v)
pattern='^([0-9]+\.[0-9])\..*'
if [[ $julia_version =~ $pattern ]]; then
	short_version=${BASH_REMATCH[1]}
else
	echo "Wrong format of version: ${julia_version}"
	return 1
fi
julia_file="julia-${julia_version}-linux-x86_64.tar.gz"
julia_link="https://julialang-s3.julialang.org/bin/linux/x64/${short_version}/${julia_file}"
julia_path=$(get_cached_file "${julia_file}" "${julia_link}")
uncompress_cached_file "${julia_path}" "$(dirname "$install_dir")" $user "$(basename "$install_dir")"

make_symlink "${install_dir}/bin/julia" /usr/local/bin/julia

startup_jl=$(get_cached_file files/startup.jl)
install_file ${startup_jl} $(get_home_dir $user) ${user}

if [[ "${use_atom}" == "1" ]]; then
  add_apt_source_manual atom "deb [arch=amd64] https://packagecloud.io/AtomEditor/atom/any/ any main" https://packagecloud.io/AtomEditor/atom/gpgkey atom.key
  install_atom_packages atom
fi

if [[ "${use_juno}" == "1" ]]; then
  install_atom_packages uber-juno
fi

if [[ "${use_dev}" == "1" ]]; then
  $(which julia) -e "using Pkg;Pkg.add([\"Revise\", \"Rebugger\", \"Debugger\", \"OhMyREPL\"]);Pkg.build(); using Revise; using Rebugger;using Debugger; using OhMyREPL"
fi

if [[ ! "${which_python}" == "" ]]; then
#  $(which julia) -e "using Pkg;Pkg.add([\"PyCall\"]);ENV[\"PYTHON\"]=\"${which_python}\";  ENV["PYCALL_DEBUG_BUILD"]=\"yes\"; Pkg.build(\"PyCall\"); using PyCall"
  $(which julia) -e "using Pkg;Pkg.add([\"PyCall\"]);ENV[\"PYTHON\"]=\"${which_python}\"; Pkg.build(\"PyCall\"); using PyCall"
fi

#$(which julia) -e 'using Pkg;Pkg.add(["Revise", "IJulia", "Rebugger", "RCall", "Knet", "Plots", "StatsPlots" , "DataFrames", "JLD", "Flux", "Debugger", "Weave"]);ENV["PYTHON"]=""; Pkg.build(); using Revise; using IJulia; using Rebugger; using RCall; using Knet; using Plots; using StatsPlots; using DataFrames; using JLD; using Flux; using Debugger'

