#!/bin/bash
# install python virtual environment

wrkspace=/software/util/JupyterLab

ML_LIBS="pybrain ray theano scikit-learn nltk"

MODULES="GCC/12.3.0 OpenMPI/4.1.5 Python/3.11.3"


PIP_REQUIRE_VIRTUALENV=true
PYTHONNOUSERSITE=true

hostnamed=$(hostname -d)

if ! echo "$hostnamed" | grep "hpc.tu-dresden.de" 2>/dev/null >/dev/null; then
	echo "You must run this on the clusters of the HPC system of the TU Dresden."
	exit 1
fi

if [[ -z $LMOD_CMD ]]; then
	echo "\$LMOD_CMD is not defined. Cannot run this script without module/lmod"
	exit 2
fi

if [[ ! -e $LMOD_CMD ]]; then
	echo "\$LMOD_CMD ($LMOD_CMD) file cannot be found. Cannot run this script without module/lmod"
	exit 2
fi

cname=$(basename -s .hpc.tu-dresden.de $hostnamed)
echo "Cluster: $cname"
#; sleep 1

function module_load(){
	local MODULES="$1"
	for module in $MODULES; do
		echo "Loading module: $module"
		module load $module
	done
}

function check_libs(){
	cat > $wrkspace/share/check_libs.py <<EOF
from importlib import import_module

libnames = $1

def check_libs(libnames):
    for x in range(len(libnames)):
        try:
            import_module(libnames[x])
        except:
            print(libnames[x] + " - failed")
        else:
            print(libnames[x] + " - ok")

check_libs(libnames)
EOF
	python3 share/check_libs.py #| tee $logfile
}

function check_torch(){
check_libs "['bs4', 'scrapy',
          'matplotlib', 'plotly', 'seaborn',
          'numpy', 'scipy', 'sympy',
          'pandarallel', 'dask', 'mpi4py', 'ipyparallel',
          'netCDF4', 'xarray']"
check_libs "['pybrain', 'ray', 'theano', 'sklearn', 'nltk',
            'torch', 'torchvision', 'torchaudio']"
}


# install base packages
function base_pkgs(){
	pip install ipykernel ipywidgets
	pip install beautifulsoup4 scrapy     # web scrape tools
	pip install nbformat==5.0.2 # for plotly
	pip install matplotlib plotly seaborn # plot/data visualization tools
}

function sci_pkgs(){
	pip install ipykernel
	pip install numpy scipy sympy # math libs
	pip install pandarallel dask mpi4py ipyparallel
	pip install netcdf4
	pip install "xarray[complete]"
}


function create_venv(){
	local venv="$1"
	local logfile=~/install_$(basename $1)-kernel-$cname.log
	python3 -m venv --system-site-packages $venv
	source $venv/bin/activate
	echo $logfile

	pip install --upgrade pip > $logfile

	python --version
}

function tensor_kernel(){
	local logfile=~/install_$(basename $1)-kernel-$cname.log

	create_venv "$1"

	base_pkgs >> $logfile
	sci_pkgs >> $logfile


	pip install $ML_LIBS
	module load TensorFlow/2.9.1
	#pip install tensorflow==2.14.1 # machine learning
	# MLpy # not working
	# Keras
	# Pytorch

	if [ "$cname" == "alpha" ]; then
		pip install nvidia-cudnn-cu12
		# tensorflow-gpu is not used anymore
	fi

	check_libs "['bs4', 'scrapy',
	    'matplotlib', 'plotly', 'seaborn',
	    'numpy', 'scipy', 'sympy',
	    'pandarallel', 'dask', 'mpi4py', 'ipyparallel',
	    'netCDF4', 'xarray']"
	check_libs "['pybrain', 'ray', 'theano', 'sklearn', 'nltk',
	    'tensorflow']"

	deactivate
}

function pytorchv1_kernel(){
	local logfile=~/install_$(basename $1)_v1-kernel-$cname.log
	#local torch_ver=1.11.0 # from pip
	local torch_ver=1.13.1 # from module system

	module load PyTorch/$torch_ver

	create_venv "$1_v1"

	base_pkgs >> $logfile
	sci_pkgs >> $logfile

	pip install $ML_LIBS

	if [ "$cname" == "alpha" ]; then
		#pip install nvidia-cudnn-cu12
		module load cuDNN/8.6.0.163-CUDA-11.8.0
		pip3 install torchvision torchaudio
	else
		#pip3 install torch==$torch_ver torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
		pip3 install torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
	fi

	check_torch

	deactivate
}

function pytorchv2_kernel(){
	local logfile=~/install_$(basename $1_v2)-kernel-$cname.log
	local torch_ver=2.1.2-CUDA-12.1.1

	module load PyTorch/$torch_ver

	create_venv "$1_v2"

	base_pkgs >> $logfile
	sci_pkgs >> $logfile

	pip install $ML_LIBS

	if [ "$cname" == "alpha" ]; then
		#pip install nvidia-cudnn-cu12
		#module load cuDNN/8.6.0.163-CUDA-11.8.0
		# tensorflow-gpu is not used anymore
		pip3 install torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
	else
		pip3 install torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
	fi

	check_torch

	deactivate
}

function pytorch_kernel(){
	local logfile=~/install_$(basename $1)-kernel-$cname.log

	pytorchv1_kernel $1
	pytorchv2_kernel $1
}


set -e

module reset
case $cname in
	barnard)
		module load release/23.10
		module_load "${MODULES}"
		;;
	alpha)
		module load release/23.04
		module_load "${MODULES}"
		module load CUDA/12.0.0
		;;
	romeo)
		module load release/23.04
		module_load "${MODULES}"
		;;
	*)
		echo unknown cluster
		exit
esac

cd $wrkspace

# install packages
#pandas pandarallel
#lightgbm
#eli5
#bob
#bokeh
#joblib
#dispy


###########################
# Machine Learning kernel #
###########################
if [ ! -d "$cname/share/tensorflow" ]; then
	tensor_kernel "$cname/share/tensorflow"
fi

pytorch_kernel "$cname/share/pytorch"

# creating kernel inside workspaces
#pytorch_kernel /beegfs/ws/1/$(whoami)-pytorch2_alpha_test
