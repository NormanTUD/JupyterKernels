#!/bin/bash
# install python virtual environment

wrkspace=/software/util/JupyterLab

ML_LIBS="pybrain ray theano scikit-learn nltk"

MODULES="GCC/12.3.0 OpenMPI/4.1.5 Python/3.11.3"


PIP_REQUIRE_VIRTUALENV=true
PYTHONNOUSERSITE=true

hostnamed=$(hostname -d)

Color_Off='\033[0m'
Green='\033[0;32m'
Red='\033[0;31m'

function red_text {
	echo -ne "${Red}$1${Color_Off}"
}

function green_text {
	echo -ne "${Green}$1${Color_Off}"
}

function _tput {
	set +e
	CHAR=$1

	if ! command -v tput 2>/dev/null >/dev/null; then
		red_text "tput not installed" >&2
		set +e
		return 0
	fi

	if [[ -z $CHAR ]]; then
		red_text "No character given" >&2
		set +e
		return 0
	fi

	if ! tty 2>/dev/null >/dev/null; then
		echo ""
		set +e
		return 0
	fi

	tput $CHAR
	set +e
}

function green_reset_line {
	_tput cr
	_tput el
	green_text "$1"
}

function red_reset_line {
	_tput cr
	_tput el
	red_text "$1"
}

function module_load(){
	local MODULES="$1"
	for module in $MODULES; do
		green_reset_line "Loading module: $module"
		module load $module >/dev/null || {
			red_text "Failed to load $module"
			exit 4
		}
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

if ! echo "$hostnamed" | grep "hpc.tu-dresden.de" 2>/dev/null >/dev/null; then
	red_text "You must run this on the clusters of the HPC system of the TU Dresden.\n"
	exit 1
fi

if [[ -z $LMOD_CMD ]]; then
	red_text "\$LMOD_CMD is not defined. Cannot run this script without module/lmod\n"
	exit 2
fi

if [[ ! -e $LMOD_CMD ]]; then
	red_text "\$LMOD_CMD ($LMOD_CMD) file cannot be found. Cannot run this script without module/lmod\n"
	exit 3
fi

cname=$(basename -s .hpc.tu-dresden.de $hostnamed)
green_text "Cluster: $cname\n"
#; sleep 1


module reset  >/dev/null || {
	red_text "Failed to reset modules\n"
	exit 4
}

case $cname in
	barnard)
		module load release/23.10 >/dev/null || {
			red_text "Failed to load release/23.10\n"
			exit 4
		}
		module_load "${MODULES}"
		;;
	alpha)
		#module load release/23.04 || { # Old release, but fails with GCC/12.3.0
		module load release/24.04 >/dev/null || {
			red_text "Failed to load release/23.04\n"
			exit 4
		}
		module  load CUDA/12.0.0 >/dev/null || {
			red_text "Failed to load CUDA/12.0.0\n"
			exit 4
		}
		module_load "${MODULES}"
		;;
	romeo)
		module load release/23.04 >/dev/null || {
			red_text "Failed to load release/23.04\n"
			exit 4
		}
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
