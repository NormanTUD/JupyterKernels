#!/bin/bash

CONFIG_JSON=$(echo '
		{
		  "same_modules_everywhere": "GCC/12.3.0 OpenMPI/4.1.5 Python/3.11.3",
		  "modules_by_cluster": {
		    "barnard": "release/23.10",
		    "alpha": "release/24.04 CUDA/12.2.0",
		    "romeo": "release/23.04"
		  },
		  "pip_module_groups": {
		    "ml_libs": "pybrain ray theano scikit-learn nltk",
		    "base_pks": "ipykernel ipywidgets beautifulsoup4 scrapy nbformat==5.0.2 matplotlib plotly seaborn",
		    "sci_pks": "ipykernel numpy scipy sympy pandarallel dask mpi4py ipyparallel netcdf4 xarray[complete]",
		    "torchvision_torchaudio": {
		      "pip_complex": {
			"alpha": "torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121",
			"barnard": "torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu",
			"romeo": "torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu"
		      }
		    },
		    "nvidia-cudnn-cu12": {
		      "pip_complex": {
			"alpha": "nvidia-cudnn-cu12"
		      }
		    }
		  },
		  "kernels": {
		    "tensorflow": {
		      "name": "TensorFlow (Machine Learning)",
		      "tests": ["check_tensorflow"],
		      "pip_dependencies": ["base_pks", "sci_pks", "ml_libs", "nvidia-cudnn-cu12"]
		    },
		    "pytorch": {
		      "name": "PyTorch (Machine Learning)",
		      "tests": ["check_torchv2"],
		      "pip_dependencies": ["base_pks", "sci_pks", "ml_libs", "torchvision_torchaudio"]
		    }
		  }
		}
	'
)

FROZEN=""

{ # Hack to prevent re-reading the file while it is still running
	ORIGINAL_PWD=$(pwd)
	#wrkspace=/software/util/JupyterLab
	wrkspace=/home/s3811141/test/randomtest_53262/JupyterKernels/JL
	mkdir -p $wrkspace || {
		echo "Cannot create $wrkspace"
		exit 123
	}

	export LD_LIBRARY_PATH=.:$LD_LIBRARY_PATH

	function join_by {
		local d=${1-} f=${2-}
		if shift 2; then
			printf %s "$f" "${@/#/$d}"
		fi
	}

	generate_progress_bar() {
		local current_progress=$1
		local total_progress=$2

		if ! [[ "$current_progress" =~ ^[0-9]+$ ]] || ! [[ "$total_progress" =~ ^[0-9]+$ ]]; then
			echo "Fehler: Beide Parameter müssen positive Ganzzahlen sein, sind $current_progress/$total_progress." >&2
			return 1
		fi

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

	if [[ ! -e jq ]]; then
		red_text "\njq not found. Please install it, e.g. via apt-get install jq or download it using https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64\n"
		exit 101
	fi

	if ! echo "$CONFIG_JSON" | ./jq 2>/dev/null >/dev/null; then
		red_text "The JSON string has a syntax error. Cannot continue.\n"
		exit 100
	fi

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

		#if ! tty 2>/dev/null >/dev/null; then
		#	echo ""
		#	set +e
		#	return 0
		#fi

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

		MAXMODNR=$(echo "$MODULES" | sed -e 's#\s#\n#g' | wc -l)

		i=0
		PBAR=$(generate_progress_bar $i $MAXMODNR)

		green_reset_line "$PBAR➤Loading modules: $MODULES"
		for module in $MODULES; do
			PBAR=$(generate_progress_bar $i $MAXMODNR)
			green_reset_line "$PBAR➤Loading module: $module ($(($i+1))/$MAXMODNR)"
			module load $module >/dev/null 2>/dev/null || {
				red_text "❌Failed to load $module"
				exit 4
			}
			i=$((i+1))
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

		FROZEN=$(pip list --format=freeze)
		green_reset_line "✅Module $TO_INSTALL installed."
	}

	function ppip {
		TO_INSTALL="$1"

		i=0
		MAXMODNR=$(echo "$TO_INSTALL" | sed -e 's#\s#\n#g' | wc -l)
		PBAR=$(generate_progress_bar $i $MAXMODNR)
		green_reset_line "$PBAR➤Installing $TO_INSTALL"
		pip3 --upgrade pip 2>/dev/null >/dev/null

		for ELEM in $(echo "$TO_INSTALL"); do
			if ! echo "$FROZEN" | grep "$ELEM" 2>/dev/null >/dev/null; then
				PBAR=$(generate_progress_bar $i $MAXMODNR)
				green_reset_line "$PBAR➤Installing $ELEM ($(($i+1))/$MAXMODNR)"
				pip3 -q install $ELEM 2>/dev/null >/dev/null || {
					red_text "\n❌Could not install $ELEM.\n"
					exit 30
				}

				FROZEN=$(pip list --format=freeze)
			fi

			i=$(($i+1))
		done

		green_reset_line "✅Modules $TO_INSTALL installed."
	}

	function check_libs(){
		MODS="$1"
		MODS=$(echo "$MODS" | sed -e 's#\s\s*# #g' -e 's#\s#, #g' -e "s#^#'#" -e "s#\$#'#")
		yellow_text "\nChecking libs ($MODS)...\n"
		echo "
from importlib import import_module

libnames = [$MODS]

def check_libs(libnames):
    for x in range(len(libnames)):
        try:
            import_module(libnames[x])
        except:
            print(libnames[x] + ' - failed')
        else:
            print(libnames[x] + ' - ok')

check_libs(libnames)
" | python3
		exit_code=$?
		echo "Exit-Code for check lib: $exit_code"
	}

	function check_base_libs {
		check_libs "bs4 scrapy matplotlib plotly seaborn numpy scipy sympy pandarallel dask mpi4py ipyparallel netCDF4 xarray pybrain ray theano sklearn nltk"
	}

	function check_tensorflow {
		yellow_text "\nCheck tensorflow...\n"

		check_base_libs
		check_libs "tensorflow"
	}

	function check_torchv1(){
		yellow_text "\nChec torchv1\n"
		red_text "\nNOT YET IMPLEMENTED\n"
	}

	function check_torchv2(){
		yellow_text "\nCheck torchv2...\n"

		check_base_libs
		check_libs "torch torchvision torchaudio"
	}

	function create_start_kernel_sh {
		shortname="$1"
		_name="$2"
		_module_list="$3"

		opt_dir="$wrkspace/$cluster_name/opt/"

		mkdir -p $opt_dir || {
			red_text "\nCannot create $opt_dir\n"
			return
		}

		kernel_start_file="$opt_dir/start-kernel.sh"

		echo "#!/bin/bash

CONNFILE=\${1}

set -euo pipefail

echo '========================================================='
echo 'Starting ${_name}...'

module reset
module load ${_module_list}

PYVENV_PATH=$wrkspace/$cluster_name/share/$shortname

source \$PYVENV_PATH/bin/activate

python \
  -m ipykernel_launcher \
  -f \${CONNFILE}

echo '========================================================='
" > $kernel_start_file

		if [[ -e "$kernel_start_file" ]]; then
			green_text "\n$kernel_start_file succesfully created\n"
		else
			red_text "\n$kernel_start_file succesfully created\n"
		fi
	}

	function create_kernel_json {
		shortname="$1"
		_name="$2"

		if [[ ! -e $wrkspace/$cluster_name/opt/start-kernel.sh ]]; then
			red_text "!!! $wrkspace/$cluster_name/opt/start-kernel.sh not found !!!"
		fi

		echo "{
			\"display_name\": \"$_name\",
			\"argv\": [
				\"$wrkspace/$cluster_name/opt/start-kernel.sh\",
				\"{connection_file}\"
			],
			\"env\": {},
			\"language\": \"python\",
			\"metadata\": {
				\"debugger\": true
			}
		}" > $ORIGINAL_PWD/kernel_${shortname}.json
	}

	function pytorchv1_kernel(){
		yellow_text "\n➤Install PyTorchv1 Kernel\n"
		local logfile=~/install_$(basename $1)_v1-kernel-$cluster_name.log
		#local torch_ver=1.11.0 # from pip
		local torch_ver=1.13.1 # from module system

		module load PyTorch/$torch_ver

		install_base_sci_ml_pkgs

		if [ "$cluster_name" == "alpha" ]; then
			#ppip nvidia-cudnn-cu12
			module_load cuDNN/8.6.0.163-CUDA-11.8.0
			ppip torchvision torchaudio
		else
			#ppip torch==$torch_ver torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
			ppip_complex torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
		fi

		check_torchv1

		deactivate
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

	green_reset_line "Resetting modules..."

	module reset >/dev/null 2>/dev/null || {
		red_text "Failed to reset modules\n"
		exit 4
	}

	green_reset_line "Modules resetted"

	same_modules_everywhere=$(echo "$CONFIG_JSON" | ./jq -r '.same_modules_everywhere')

	current_cluster_load=$(echo "$CONFIG_JSON" | ./jq -r --arg cluster_name "$cluster_name" '.modules_by_cluster[$cluster_name]')

	current_load="$current_cluster_load $same_modules_everywhere"

	green_reset_line "➤Loading modules for $cluster_name..."

	module_load "$current_load"

	green_text "\n➤Python version: $(python --version)"

	echo "$CONFIG_JSON" | ./jq -c '.kernels | to_entries[]' | while IFS= read -r kernel_entry; do
		kernel_key=$(echo "$kernel_entry" | ./jq -r '.key')
		kernel_name=$(echo "$kernel_entry" | ./jq -r '.value.name')
		kernel_tests=$(echo "$kernel_entry" | ./jq -r '.value.tests | join(" ")')
		kernel_pip_dependencies=$(echo "$kernel_entry" | ./jq -r '.value.pip_dependencies | join(" ")')

		kernel_dir="$wrkspace/$cluster_name/share/$kernel_key"

		if [[ ! -d $kernel_dir ]]; then
			green_reset_line "➤Trying to create virtualenv $kernel_dir"

			python3 -m venv --system-site-packages $kernel_dir || {
				red_text "\n➤python3 -m venv --system-site-packages $kernel_dir failed\n"
				exit 10
			}
			green_reset_line "✅Virtualenv $kernel_dir created"
		else
			green_reset_line "✅Virtualenv $kernel_dir already exists"
		fi

		green_reset_line "✅Activating virtualenv $kernel_dir/bin/activate"
		if [[ ! -e "$kernel_dir/bin/activate" ]]; then
			red_text "\n$kernel_dir/bin/activate could not be found\n"
			exit 199
		fi

		source $kernel_dir/bin/activate

		pip install --upgrade pip

		FROZEN=$(pip list --format=freeze)

		for pip_dependency_group in $kernel_pip_dependencies; do
			yellow_text "\nPIP-Dependency group for $kernel_name: $pip_dependency_group:\n"
			dependency_value=$(echo "$CONFIG_JSON" | ./jq -r ".pip_module_groups[\"$pip_dependency_group\"]")
			if [[ $? -eq 0 ]]; then
				# Check for pip_complex for the current cluster
				pip_complex_value=$(echo "$CONFIG_JSON" | ./jq -r ".pip_module_groups[\"$pip_dependency_group\"].pip_complex[\"$cluster_name\"]" 2>/dev/null)
				if [[ $? -eq 0 ]]; then
					if [[ "$pip_complex_value" != "null" ]]; then
						ppip_complex "$pip_complex_value"
					else
						true
						#red_reset_line "Could not find .pip_module_groups[$pip_dependency_group].pip_complex[$cluster_name]}"
					fi
				else
					ppip "$dependency_value"
					#red_reset_line "Could not find .pip_module_groups[$pip_dependency_group].pip_complex[$cluster_name]}"
				fi
			else
				red_reset_line "Could not find .pip_module_groups[$pip_dependency_group]"
			fi
		done

		create_start_kernel_sh "$kernel_key" "$kernel_name" "$current_load"
		create_kernel_json "$kernel_key" "$kernel_name"

		# Iterate through tests
		green_reset_line "Iterating over tests:"
		for kernel_test in $kernel_tests; do
			green_reset_line "Running kernel-test $kernel_test"
			eval "$kernel_test"
		done

		deactivate
	done

	exit

	# install packages
	#pandas pandarallel
	#lightgbm
	#eli5
	#bob
	#bokeh
	#joblib
	#dispy
}
