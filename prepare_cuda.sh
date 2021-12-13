#!/bin/bash


cd `dirname $0`
. ./common.sh


usage="
Prepares conda with current Python and jupyter and no other packages, all for the current user.


Usage:

$(basename $0)  [--cuda-version <cuda_version>] [--driver-version <driver_version>] [--repo-path <path>]
                [--help] [--debug] [--log <output file>] 


where

 --cuda-version <cuda_version>- Version of cuda to install. Defaults to 10.1
 --repo-path                  - Alternative directory where to look for (and save) 
                                downloaded files. Defaults to /media/adam-minipc/other/debs 
                                if exists or /tmp/repo-path if it does not.
 --driver-version <version>   - Version of the nvidia driver. Will install nvidia-smi accordingly.
 --debug                      - Flag that sets debugging mode. 
 --log                        - Path to the log file that will log all meaningful commands

Example2:

$(basename $0) 

"

#if [ -z "$1" ]; then
#	echo "$usage" >&2
#	exit 0
#fi

set -x

user="$USER"

if [ -d /media/adam-minipc/other/debs/ ]; then
   repo_path=/media/adam-minipc/other/debs
else
   repo_path=/tmp/repo_path
fi
driver_version="auto"
cuda_version="10.1"
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
	-v|--driver-version)
	driver_version=$1
	shift
	;;
	-c|--cuda-version)
	cuda_version=$1
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

add_apt_source_manual cuda  "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu$(get_ubuntu_version)/x86_64/ /" "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/7fa2af80.pub" cuda.key

if [[ ! $driver_version == "auto" ]]; then
   install_apt_package nvidia-utils-${driver_version} nvidia-smi
fi

if [[ $cuda_version == "10.0" ]]; then
   install_apt_packages cuda-command-line-tools-10-0 cuda-compat-10-0 cuda-core-10-0 cuda-compiler-10-0 cuda-cudart-10-0 cuda-cudart-dev-10-0 cuda-cufft-dev-10-0 cuda-cufft-10-0 cuda-cuobjdump-10-0 cuda-cupti-10-0 cuda-curand-10-0 cuda-curand-dev-10-0 cuda-cusolver-10-0 cuda-cusolver-dev-10-0 cuda-cusparse-10-0 cuda-cusparse-dev-10-0 cuda-gdb-src-10-0 cuda-gdb-10-0 cuda-gpu-library-advisor-10-0 cuda-libraries-10-0 cuda-libraries-dev-10-0 cuda-license-10-0 cuda-memcheck-10-0 cuda-minimal-build-10-0 cuda-misc-headers-10-0 cuda-npp-10-0 cuda-npp-dev-10-0 cuda-nvcc-10-0 cuda-nvdisasm-10-0 cuda-nvgraph-10-0 cuda-nvgraph-dev-10-0 cuda-nvjpeg-10-0 cuda-nvjpeg-dev-10-0 cuda-nvml-dev-10-0 cuda-nvprof-10-0 cuda-nvprune-10-0 cuda-nvrtc-10-0 cuda-nvrtc-dev-10-0 cuda-nvtx-10-0 
   cuda_prefix="/usr/local/cuda-10.0"
elif [[ $cuda_version == "10.1" ]]; then
   install_apt_packages cuda-command-line-tools-10-1 cuda-compat-10-1 cuda-core-10-1 cuda-compiler-10-1 cuda-cudart-10-1 cuda-cudart-dev-10-1 cuda-cufft-dev-10-1 cuda-cufft-10-1 cuda-cuobjdump-10-1 cuda-cupti-10-1 cuda-curand-10-1 cuda-curand-dev-10-1 cuda-cusolver-10-1 cuda-cusolver-dev-10-1 cuda-cusparse-10-1 cuda-cusparse-dev-10-1 cuda-gdb-src-10-1 cuda-gdb-10-1 cuda-gpu-library-advisor-10-1 cuda-libraries-10-1 cuda-libraries-dev-10-1 cuda-license-10-1 cuda-memcheck-10-1 cuda-minimal-build-10-1 cuda-misc-headers-10-1 cuda-npp-10-1 cuda-npp-dev-10-1 cuda-nvcc-10-1 cuda-nvdisasm-10-1 cuda-nvgraph-10-1 cuda-nvgraph-dev-10-1 cuda-nvjpeg-10-1 cuda-nvjpeg-dev-10-1 cuda-nvml-dev-10-1 cuda-nvprof-10-1 cuda-nvprune-10-1 cuda-nvrtc-10-1 cuda-nvrtc-dev-10-1 cuda-nvtx-10-1
   cuda_prefix="/usr/local/cuda-10.1"
elif [[ $cuda_version == "11.1" ]]; then
   install_apt_packages cuda-toolkit-11-1 
   cuda_prefix="/usr/local/cuda-11.1"
elif [[ $cuda_version == "11.0" ]]; then
   install_apt_packages cuda-toolkit-11-0 
   cuda_prefix="/usr/local/cuda-11.0"
fi



textfile /opt/cuda-${cuda_version}.env "export PATH=\$PATH:/usr/local/cuda-${cuda_version}/bin
export CUDADIR=/usr/local/cuda-${cuda_version}
export CUDA_PATH=/usr/local/cuda-${cuda_version}
export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:/usr/local/cuda-${cuda_version}/lib64" root

add_ppa graphics-drivers/ppa

if [[ $driver_version != "auto" ]]; then
   install_apt_packages nvidia-utils-${driver_version}
fi

sample_dir="$(get_home_dir ${user})/tmp"
get_git_repo https://github.com/NVIDIA/cuda-samples.git $(get_home_dir ${user})/tmp cuda-samples
sample_dir="${sample_dir}/cuda-samples/Samples"

install_apt_packages build-essential
source /opt/cuda-${cuda_version}.env
pushd "${sample_dir}/deviceQuery"
make
popd
pushd "${sample_dir}/bandwidthTest"
make
popd

if which optirun>/dev/null; then
	optirun ${sample_dir}/bandwidthTest/bandwidthTest
else
	${sample_dir}/bandwidthTest/bandwidthTest
fi
