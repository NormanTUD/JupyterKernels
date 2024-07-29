#!/bin/bash
# install python virtual environment

#wrkspace=/software/util/JupyterLab
wrkspace=/home/s3811141/test/randomtest_53262/JupyterKernels/JL

ML_LIBS=(
	"pybrain"
	"ray"
	"theano"
	"scikit-learn nltk"
)

SCI_PKGS=(
	"ipykernel"
	"numpy"
	"scipy"
	"sympy"
	"pandarallel"
	"dask"
	"mpi4py"
	"ipyparallel"
	"netcdf4"
	"xarray[complete]"
)

BASE_PKGS=(
	"ipykernel"
	"ipywidgets"
	"beautifulsoup4"
	"scrapy"
	"nbformat==5.0.2"
	"matplotlib"
	"plotly"
	"seaborn"
)

MODULES="GCC/12.3.0 OpenMPI/4.1.5 Python/3.11.3"


PIP_REQUIRE_VIRTUALENV=true
PYTHONNOUSERSITE=true

hostnamed=$(hostname -d)

Color_Off='\033[0m'
Green='\033[0;32m'
Red='\033[0;31m'

function echoerr {
	echo -ne "$@" 1>&2
}

function red_text {
	echoerr "${Red}$1${Color_Off}"
}

function green_text {
	echoerr "${Green}$1${Color_Off}"
}

function yellow_text {
	echoerr "\e\033[0;33m$1\e[0m"
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
		module load $module >/dev/null 2>/dev/null || {
			red_text "Failed to load $module"
			exit 4
		}
	done
}

function check_libs(){
	yellow_text "\nCheck libs...\n"
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
	yellow_text "\nCheck torch...\n"
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
	yellow_text "\nInstalling base packages\n"

	for key in "${!BASE_PKGS[@]}"; do
		this_base_lib=$BASE_PKGS[$key]
		green_reset_line "Installing $this_base_lib"
		pip install $this_base_lib 2>/dev/null >/dev/null || {
			red_text "\nFailed to install $this_base_lib\n"
			exit 13
		}
	done
}

function sci_pkgs(){
	yellow_text "\nInstalling scientific packages\n"

	for key in "${!SCI_PKGS[@]}"; do
		this_sci_lib=$SCI_PKGS[$key]
		green_reset_line "Installing $this_sci_lib"
		pip install $this_sci_lib 2>/dev/null >/dev/null || {
			red_text "\nFailed to install $this_sci_lib\n"
			exit 13
		}
	done
}

function ml_pkgs () {
	green_reset_line "Installing ML libs into venv..."
	for key in "${!ML_LIBS[@]}"; do
		this_ml_lib=$ML_LIBS[$key]
		green_reset_line "Installing $this_ml_lib"
		pip install $this_ml_lib >> $logfile || {
			red_text "\nFailed to install $this_ml_lib\n"
			exit 13
		}
	done
}

function create_venv(){
	local venv="$1"
	local logfile="$2"

	yellow_text "\nCreating virtual environment ($venv)\n"

	green_reset_line "Trying to create virtualenv $venv"

	python3 -m venv --system-site-packages $venv || {
		red_text "\npython3 -m venv --system-site-packages $venv failed\n"
		exit 10
	}

	green_reset_line "Loading the previously created virtual environment"
	source $venv/bin/activate || {
		red_text "\nSourcing $venv/bin/activate failed\n"
		exit 11
	}
	green_reset_line "Using logfile $logfile"

	green_reset_line "Upgrading pip..."
	pip install --upgrade pip >> $logfile

	echo -e "\nPython version: $(python --version)"
}

function tensorflow_kernel(){
	name="$1"

	yellow_text "\nInstall Tensorflow Kernel $name\n"
	local logfile=~/install_$(basename $name)-kernel-$cname.log

	create_venv "$name" "$logfile"

	base_pkgs
	sci_pkgs
	ml_pkgs

	green_reset_line "Installing ML libs into venv..."
	for key in "${!ML_LIBS[@]}"; do
		this_ml_lib=$ML_LIBS[$key]
		green_reset_line "Installing $this_ml_lib"
		pip install $this_ml_lib >> $logfile || {
			red_text "\nFailed to install $this_ml_lib\n"
			exit 13
		}
	done

	module load TensorFlow/2.9.1 2>/dev/null >/dev/null || {
		red_text "Could not load TensorFlow/2.9.1"
		exit 20
	}
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
	yellow_text "\nInstall PyTorchv1 Kernel\n"
	local logfile=~/install_$(basename $1)_v1-kernel-$cname.log
	#local torch_ver=1.11.0 # from pip
	local torch_ver=1.13.1 # from module system

	module load PyTorch/$torch_ver

	create_venv "$1_v1" $logfile

	base_pkgs
	sci_pkgs
	ml_pkgs

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
	yellow_text "\nInstall PyTorchv2 Kernel\n"
	local logfile=~/install_$(basename $1_v2)-kernel-$cname.log
	local torch_ver=2.1.2-CUDA-12.1.1

	module load PyTorch/$torch_ver 2>/dev/null >/dev/null || {
		red_text "\nFailed to load PyTorch/$torch_ver\n"
		exit 12
	}

	create_venv "$1_v2" "$logfile"

	base_pkgs
	sci_pkgs
	ml_pkgs


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
	yellow_text "\nInstalling pytorch kernel\n"
	local logfile=~/install_$(basename $1)-kernel-$cname.log

	#pytorchv1_kernel $1 # TODO! V1 Kernel für Alpha
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


if [[ ! -d "$wrkspace" ]]; then
	echo ""
	red_text "workspace $wrkspace cannot be found. Cannot continue.\n"
	exit 6
fi

if [[ ! -w "$wrkspace" ]]; then
	echo ""
	red_text "workspace $wrkspace is not writable. Cannot continue.\n"
	exit 7
fi

cd $wrkspace

green_reset_line "Resetting modules..."
module reset >/dev/null 2>/dev/null || {
	red_text "Failed to reset modules\n"
	exit 4
}
green_reset_line "Modules resetted"

case $cname in
	barnard)
		module load release/23.10 >/dev/null 2>/dev/null || {
			red_text "Failed to load release/23.10\n"
			exit 4
		}
		module_load "${MODULES}"
		;;
	alpha)
		#module load release/23.04 || { # Old release, but fails with GCC/12.3.0
		module load release/24.04 >/dev/null 2>/dev/null || {
			red_text "Failed to load release/23.04\n"
			exit 4
		}
		module load CUDA/12.2.0 >/dev/null 2>/dev/null || {
			red_text "Failed to load CUDA/12.2.0\n"
			exit 4
		}
		module_load "${MODULES}"
		;;
	romeo)
		module load release/23.04 >/dev/null 2>/dev/null || {
			red_text "Failed to load release/23.04\n"
			exit 4
		}
		module_load "${MODULES}"
		;;
	*)
		echo unknown cluster
		exit
esac

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
	tensorflow_kernel "$cname/share/tensorflow"
else
	yellow_text "$cname/share/tensorflow already exists"
fi

if [ ! -d "$cname/share/pytorch" ]; then
	pytorch_kernel "$cname/share/pytorch"
else
	yellow_text "$cname/share/pytorch already exists"
fi

# creating kernel inside workspaces
#pytorch_kernel /beegfs/ws/1/$(whoami)-pytorch2_alpha_test
