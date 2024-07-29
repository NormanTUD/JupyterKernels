#!/bin/bash
{ # Hack to prevent re-reading the file while it is still running
	# install python virtual environment

	#wrkspace=/software/util/JupyterLab
	wrkspace=/home/s3811141/test/randomtest_53262/JupyterKernels/JL
	mkdir -p $wrkspace

	function join_by {
		local d=${1-} f=${2-}
		if shift 2; then
			printf %s "$f" "${@/#/$d}"
		fi
	}

	generate_progress_bar() {
		local current_progress=$1
		local total_progress=$2

		# Überprüfen, ob die Eingaben gültige positive Ganzzahlen sind
		if ! [[ "$current_progress" =~ ^[0-9]+$ ]] || ! [[ "$total_progress" =~ ^[0-9]+$ ]]; then
			echo "Fehler: Beide Parameter müssen positive Ganzzahlen sein, sind $current_progress/$total_progress." >&2
			return 1
		fi

		# Überprüfen, ob der aktuelle Fortschritt den Gesamtfortschritt nicht überschreitet
		if [ "$current_progress" -gt "$total_progress" ]; then
			echo "Fehler: Der aktuelle Fortschritt darf den Gesamtfortschritt nicht überschreiten ($current_progress/$total_progress)." >&2
			return 1
		fi

		local bar_length=30
		local filled_length=$((bar_length * current_progress / total_progress))
		local empty_length=$((bar_length - filled_length))

		local bar=""
		for ((i = 0; i < filled_length; i++)); do
			bar="${bar}#"
		done
		for ((i = 0; i < empty_length; i++)); do
			bar="${bar} "
		done

		echo "[${bar}] "
	}

	ML_LIBS=(
		"pybrain"
		"ray"
		"theano"
		"scikit-learn nltk"
	)

	BASE_PKGS_LIST=(
		"ipykernel"
		"ipywidgets"
		"beautifulsoup4"
		"scrapy"
		"nbformat==5.0.2"
		"matplotlib"
		"plotly"
		"seaborn"
	)

	BASE_SCI_PKGS=(
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

	BASE_MODULES="GCC/12.3.0 OpenMPI/4.1.5 Python/3.11.3"


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
		green_reset_line "➤Loading modules: $MODULES"

		for module in $MODULES; do
			green_reset_line "➤Loading module: $module"
			module load $module >/dev/null 2>/dev/null || {
				red_text "❌Failed to load $module"
				exit 4
			}
		done

		green_reset_line "✅Loaded modules: $MODULES"
	}

	function ppip_complex {
		TO_INSTALL="$1"

		green_reset_line "➤Installing $TO_INSTALL"
		green_reset_line "➤Installing $ELEM"

		pip3 install $TO_INSTALL 2>/dev/null >/dev/null || {
			red_text "\n❌Could not install $TO_INSTALL.\n"
			exit 30
		}

		green_reset_line "✅Module $TO_INSTALL installed."
	}

	function ppip {
		TO_INSTALL="$1"

		i=0
		PBAR=$(generate_progress_bar $i $(echo "$TO_INSTALL" | sed -e 's#\s#\n#g' | wc -l))
		green_reset_line "$PBAR➤Installing $TO_INSTALL"

		for ELEM in $(echo "$TO_INSTALL"); do
			PBAR=$(generate_progress_bar $i $(echo "$TO_INSTALL" | sed -e 's#\s#\n#g' | wc -l))
			green_reset_line "$PBAR➤Installing $ELEM"
			pip3 install $ELEM 2>/dev/null >/dev/null || {
				red_text "\n❌Could not install $TO_INSTALL.\n"
				exit 30
			}
			i=$(($i+1))
		done

		PBAR=$(generate_progress_bar $i $(echo "$TO_INSTALL" | sed -e 's#\s#\n#g' | wc -l))
		green_reset_line "$PBAR✅Modules $TO_INSTALL installed."
	}

	function check_libs(){
		MODS="$1"
		MODS=$(echo "$MODS" | sed -e 's#\s\s*# #g' -e 's#\s#, #g' -e "s#^#'#" -e "s#\$#'#")
		yellow_text "\nChecking libs ($MODS)...\n"
		cat > $cluster_name/share/check_libs.py <<EOF
	from importlib import import_module

	libnames = [$MODS]

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
		python3 $cluster_name/share/check_libs.py #| tee $logfile
	}

	function check_base_libs {
		check_libs "bs4 scrapy matplotlib plotly seaborn numpy scipy sympy pandarallel dask mpi4py ipyparallel netCDF4 xarray pybrain ray theano sklearn nltk"
	}

	function check_tensorflow {
		yellow_text "\nCheck tensorflow...\n"

		check_base_libs
		check_libs "tensorflow"
	}

	function check_torch(){
		yellow_text "\nCheck torch...\n"

		check_base_libs
		check_libs "torch torchvision torchaudio"
	}


	# install base packages
	function base_pkgs(){
		BASE_PKGS_STR=$(join_by " " ${BASE_PKGS_LIST[@]})
		yellow_text "\n\n➤Installing base packages $BASE_PKGS_STR\n"

		ppip "$BASE_PKGS_STR"
	}

	function sci_pkgs(){
		SCI_PKGS_STR=$(join_by " " "${BASE_SCI_PKGS[@]}")
		yellow_text "\n\n➤Installing scientific packages $SCI_PKGS_STR\n"

		ppip "$SCI_PKGS_STR"
	}

	function ml_pkgs {
		green_reset_line "➤Installing ML libs into venv..."
		for key in "${!ML_LIBS[@]}"; do
			this_ml_lib=${ML_LIBS[$key]}
			ppip $this_ml_lib
		done
	}

	function create_venv {
		local venv="$1"
		local logfile="$2"

		yellow_text "\n➤Creating virtual environment ($venv)\n"

		if [[ ! -e "$venv/bin/activate" ]]; then
			green_reset_line "➤Trying to create virtualenv $venv"

			python3 -m venv --system-site-packages $venv || {
				red_text "\n➤python3 -m venv --system-site-packages $venv failed\n"
				exit 10
			}

			green_reset_line "➤Using logfile $logfile"

			green_reset_line "➤Upgrading pip..."
			pip3 --upgrade pip 2>/dev/null >/dev/null
		else
			green_text "\n\n$venv already exists. Not re-creating it.\n"
		fi


		green_reset_line "➤Loading the previously created virtual environment"
		source $venv/bin/activate || {
			red_text "\nSourcing $venv/bin/activate failed\n"
			exit 11
		}

		echo -e "\n➤Python version: $(python --version)"
	}

	function install_base_sci_ml_pkgs {
		base_pkgs
		sci_pkgs
		ml_pkgs
	}

	function install_tensorflow_kernel {
		name="$1"

		if [[ -d $name ]]; then
			yellow_text "\n$cluster_name/share/tensorflow already exists\n"
		else
			yellow_text "\nInstall Tensorflow Kernel $name\n"
			local logfile=~/install_$(basename $name)-kernel-$cluster_name.log

			create_venv "$name" "$logfile"

			install_base_sci_ml_pkgs

			yellow_text "\n\n➤Installing tensorflow libs into venv $name...\n"
			for key in "${!ML_LIBS[@]}"; do
				this_ml_lib=${ML_LIBS[$key]}
				green_reset_line "➤Installing tensorflow lib $this_ml_lib"
				ppip $this_ml_lib
			done

			tf_with_version="tensorflow==2.12.0"

			green_reset_line "➤Installing $tf_with_version"
			ppip $tf_with_version

			#module_load "TensorFlow/2.9.1"
			#ppip tensorflow==2.14.1 # machine learning
			# MLpy # not working
			# Keras
			# Pytorch

			if [ "$cluster_name" == "alpha" ]; then
				ppip nvidia-cudnn-cu12
				# tensorflow-gpu is not used anymore
			fi

			check_tensorflow

			deactivate
		fi
	}

	function pytorchv1_kernel(){
		yellow_text "\nInstall PyTorchv1 Kernel\n"
		local logfile=~/install_$(basename $1)_v1-kernel-$cluster_name.log
		#local torch_ver=1.11.0 # from pip
		local torch_ver=1.13.1 # from module system

		module load PyTorch/$torch_ver

		create_venv "$1_v1" $logfile

		install_base_sci_ml_pkgs

		if [ "$cluster_name" == "alpha" ]; then
			#ppip nvidia-cudnn-cu12
			module_load cuDNN/8.6.0.163-CUDA-11.8.0
			ppip torchvision torchaudio
		else
			#ppip torch==$torch_ver torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
			ppip_complex torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
		fi

		check_torch

		deactivate
	}

	function pytorchv2_kernel(){
		yellow_text "\nInstall PyTorchv2 Kernel\n"
		local logfile=~/install_$(basename $1_v2)-kernel-$cluster_name.log
		local torch_ver=2.1.2-CUDA-12.1.1

		module load PyTorch/$torch_ver 2>/dev/null >/dev/null || {
			red_text "\nFailed to load PyTorch/$torch_ver\n"
			exit 12
		}

		create_venv "$1_v2" "$logfile"

		install_base_sci_ml_pkgs


		if [ "$cluster_name" == "alpha" ]; then
			#ppip nvidia-cudnn-cu12
			#module load cuDNN/8.6.0.163-CUDA-11.8.0
			# tensorflow-gpu is not used anymore
			ppip_complex torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
		else
			ppip_complex torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
		fi

		check_torch

		deactivate
	}

	function install_pytorch_kernel(){
		name="$1"
		if [[ -d $name ]]; then
			yellow_text "\n➤Installing pytorch kernel to $name\n"
			local logfile=~/install_$(basename $1)-kernel-$cluster_name.log

			#pytorchv1_kernel $1 # TODO! V1 Kernel für Alpha
			pytorchv2_kernel $name
		else
			yellow_text "\n$cluster_name/share/pytorch already exists\n"
		fi
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

	cluster_name=$(basename -s .hpc.tu-dresden.de $hostnamed)
	green_text "Detected cluster: $cluster_name\n"
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

	green_reset_line "➤Loading modules for $cluster_name..."

	case $cluster_name in
		barnard)
			module_load "release 23.10 ${BASE_MODULES}"
			;;
		alpha)
			#module load release/23.04 # Old release, but fails with GCC/12.3.0
			module_load "release/24.04 CUDA/12.2.0 ${BASE_MODULES}"
			;;
		romeo)
			module_load "release/23.04 ${BASE_MODULES}"
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

	install_tensorflow_kernel "$cluster_name/share/tensorflow"
	install_pytorch_kernel "$cluster_name/share/pytorch"

	# creating kernel inside workspaces
	#install_pytorch_kernel /beegfs/ws/1/$(whoami)-pytorch2_alpha_test
}
