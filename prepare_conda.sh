#!/bin/bash


cd `dirname $0`
. ./common.sh


usage="
Prepares conda with current Python and jupyter and no other packages, all for the current user.


Usage:

$(basename $0)  [--conda-dir <conda dir>] [--pip-cacher <ip[:port]]
                [--help] [--debug] [--log <output file>] 


where

 --repo-path                  - Alternative directory where to look for (and save) 
                                downloaded files. Defaults to /media/adam-minipc/other/debs 
                                if exists or /tmp/repo-path if it does not.
 --conda-dir                  - Directory where to install conda. Defaults to /opt/conda
 --pip-cacher                 - Host name and port to the pip cacher. If specified it will
                                install appropriate ~/.pip/pip.conf so all pip operations will
                                be cached
 --debug                      - Flag that sets debugging mode. 
 --log                        - Path to the log file that will log all meaningful commands

Example2:

$(basename $0) 

"

if [ -z "$1" ]; then
	echo "$usage" >&2
	exit 0
fi

set -x

conda_dir="/opt/conda"
pip_cacher=""
user="$USER"

if [ -d /media/adam-minipc/other/debs/ ]; then
   repo_path=/media/adam-minipc/other/debs
else
   repo_path=/tmp/repo_path
fi

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--debug)
	debug=1
	;;
	--log)
	log=$1
	shift
	;;
	--conda-dir)
	conda_dir=$1
	shift
	;;
	--repo-path)
	repo_path=$1
	shift
	;;
	--pip-cacher)
	pip_cacher=$1
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

conda_path=${conda_dir}/bin/conda
need_to_install=1

if [ -f "${conda_path}"  ]; then
   if $(${conda_path} --version >/dev/null); then
      need_to_install=0
   fi
fi

if [[ ${need_to_install} == 1 ]]; then
   installer_path=$(get_cached_file Miniconda3-latest-Linux-x86_64.sh https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh)

   if [ -z "${installer_path}" ]; then
      errcho "Cannot download the installer"
      exit 0
   fi
   logmkdir /opt $USER
   logexec bash ${installer_path} -b -p "${conda_dir}"
   logmkdir /opt root
   logmkdir /opt/conda $USER
   export PATH="${conda_dir}/bin:$PATH"
fi

if ! $(conda --version >/dev/null); then
   export PATH="${conda_dir}/bin:$PATH"
fi

if ! $(conda --version >/dev/null); then
   errcho "Still cannot run conda"
   exit 0
fi

source ${conda_dir}/bin/activate

logexec conda install python jupyter

if [ -n "${pip_cacher}" ]; then
   logmkdir $HOME/.pip
   parse_URI "${pip_cacher}"
   
   textfile ~/.pip/pip.conf "[global]
index-url = http://${pip_cacher}/root/pypi/+simple/
trusted-host=${ip}

[search]
index = http://${pip_cacher}/root/pypi/
"  
fi

logexec pip install ipython jupyter jupyter_contrib_nbextensions jupyterthemes
logexec jt -t onedork
logexec jupyter contrib nbextension install --user


