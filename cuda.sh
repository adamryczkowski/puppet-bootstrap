wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/cuda-ubuntu1804.pin
sudo mv cuda-ubuntu1804.pin /etc/apt/preferences.d/cuda-repository-pin-600
sudo apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/7fa2af80.pub
sudo add-apt-repository "deb http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/ /"
sudo apt update


sudo apt install cuda-command-line-tools-10-1 cuda-compat-10-1 cuda-core-10-1 
cuda-compiler-10-1
cuda-cudart-10-1 
cuda-cudart-dev-10-1
cuda-cufft-dev-10-1 cuda-cufft-10-1
cuda-cuobjdump-10-1
cuda-cupti-10-1 
cuda-curand-10-1
cuda-curand-dev-10-1
cuda-cusolver-10-1
cuda-cusolver-dev-10-1
cuda-cusparse-10-1
cuda-cusparse-dev-10-1
# cuda-driver-dev-10-1
cuda-gdb-src-10-1
cuda-gdb-10-1
cuda-gpu-library-advisor-10-1
cuda-libraries-10-1
cuda-libraries-dev-10-1 cuda-license-10-1 cuda-memcheck-10-1 cuda-minimal-build-10-1 cuda-misc-headers-10-1
cuda-npp-10-1 cuda-npp-dev-10-1 cuda-nvcc-10-1 cuda-nvdisasm-10-1 cuda-nvgraph-10-1 cuda-nvgraph-dev-10-1 cuda-nvjpeg-10-1 cuda-nvjpeg-dev-10-1 cuda-nvml-dev-10-1
cuda-nvprof-10-1 cuda-nvprune-10-1 cuda-nvrtc-10-1 cuda-nvrtc-dev-10-1 
cuda-nvtx-10-1 
#cuda-nvvp-10-1 
#cuda-runtime-10-1 
