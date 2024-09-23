#!/bin/bash

{ # Hack to prevent re-reading the file while it is still running
	function displaytime {
		set +x
		local T=$1
			local D=$((T/60/60/24))
			local H=$((T/60/60%24))
			local M=$((T/60%60))
			local S=$((T%60))
			(( $D > 0 )) && printf '%d days ' $D
			(( $H > 0 )) && printf '%d hours ' $H
			(( $M > 0 )) && printf '%d minutes ' $M
			(( $D > 0 || $H > 0 || $M > 0 )) && printf 'and '
			printf '%d seconds\n' $S
	}

	function calltracer {
		LINE_AND_FUNCTION=$(caller)
		echo ""
		caller
		echo "Runtime (calltracer): $(displaytime $SECONDS), PID: $$"
	}

	trap 'calltracer' ERR

	#default_workspace='/software/util/JupyterLab'
	default_workspace='/data/horse/ws/s4122485-jupyter_kernels'
	# Initialize variables
	CONFIG_JSON=""
	wrkspace=$default_workspace

	# Function to check if a file is a JSON file
	is_json_file() {
		if [[ $1 == *.json ]]; then
			return 0
		else
			return 1
		fi
	}

	# Function to check if a parameter is a directory
	is_directory() {
		if [[ -d $1 ]]; then
			return 0
		else
			return 1
		fi
	}

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
		echo -ne "$@"
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

	# Process parameters
	for param in "$@"; do
		if is_json_file "$param"; then
			CONFIG_JSON=$(cat "$param")
		else
			wrkspace="$param"
		fi
	done



	FROZEN=""

	ORIGINAL_PWD=$(pwd)

	mkdir -p $wrkspace || {
		echo "Cannot create $wrkspace"
		exit 123
	}

	export LD_LIBRARY_PATH=.:$LD_LIBRARY_PATH

	if [[ -z $CONFIG_JSON ]]; then
		red_text "config-json-file not found\n"
		exit 1
	fi

	if [[ ! -e jq ]]; then
		red_text "\njq not found. Please install it, e.g. via apt-get install jq or download it using \n"
		wget https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64 || {
			red_text "jq not found and could not be downloaded"
			exit 101
		}

		mv jq-linux-amd64 jq || {
			red_text "Could not move jq-linux-amd64 to jq"
			exit 102
		}

		chmod +x jq || {
			red_text "Could not chmod +x jq"
			exit 103
		}
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

		pip3 install $TO_INSTALL 2>&1 > "${TO_INSTALL}_pip.log" || {
			red_text "\n❌Could not install $TO_INSTALL. Check ${TO_INSTALL}_pip.log for more details\n"
			exit 30
		}

		rm "${TO_INSTALL}_pip.log"

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
				pip3 install $ELEM 2>&1 > "${ELEM}_pip.log" || {
					red_text "\n❌Could not install $ELEM. Check ${ELEM}_pip.log for more details.\n"
					exit 30
				}

				rm "${ELEM}_pip.log"

				FROZEN=$(pip list --format=freeze)
			fi

			i=$(($i+1))
		done

		green_reset_line "✅Modules $TO_INSTALL installed."
	}

	function check_libs(){
		MODS="$1"
		MODS=$(echo "$MODS" | sed -e 's#\s\s*# #g' -e 's#\s#, #g' -e "s#^#'#" -e "s#\$#'#" -e "s#, #', '#g")
		#yellow_text "\nChecking libs ($MODS)...\n"
		echo "
import sys
from importlib import import_module

libnames = [$MODS]

def check_libs(libnames):
    ok = True
    mods_ok = []
    for x in range(len(libnames)):
        libname = libnames[x]
        try:
            import_module(libname)
        except:
            print(\"\\n\" + libname + ' - failed')
            ok = False
        else:
            mods_ok.append(libname)

    #print('Mods OK: ' + (', '.join(mods_ok)))

    if not ok:
        return 1
    return 0

sys.exit(check_libs(libnames))
" | python3 2>/dev/null
		exit_code=$?
		if [[ $exit_code -eq 0 ]]; then
			green_text "\ncheck_libs($MODS) successful"
		else
			red_text "\ncheck_libs($MODS) failed"
		fi
	}

	function check_base_libs {
		# TODO pybrain, theano, ray entfernt aus den check_base_libs
		check_libs "bs4 scrapy matplotlib plotly seaborn numpy scipy sympy pandarallel dask mpi4py ipyparallel netCDF4 xarray sklearn nltk"
	}

	function check_tensorflow {
		check_base_libs
		check_libs "tensorflow"
	}

	function check_torchv1(){
		yellow_text "\nChec torchv1\n"
		red_text "\nNOT YET IMPLEMENTED\n"
	}

	function check_torchv2(){
		check_base_libs
		check_libs "torch torchvision torchaudio"

		if command -v nvidia-smi 2>/dev/null >/dev/null; then
			TORCH_ENV=$(python3 -m torch.utils.collect_env 2>&1)

			if ! echo "$TORCH_ENV" | grep "Is CUDA available: True" 2>/dev/null >/dev/null; then
				red_text "'Is CUDA available: True' not found in python3 -m torch.utils.collect_env"
			fi

			if ! echo "$TORCH_ENV" | grep "GPU 0:" 2>/dev/null >/dev/null; then
				red_text "'GPU 0:' not found in python3 -m torch.utils.collect_env"
			fi

		fi
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

		kernel_start_file="$opt_dir/start-${shortname}-kernel.sh"

		echo "#!/bin/bash

CONNFILE=\${1}

set -euo pipefail

echo '========================================================='
echo 'Starting ${_name}...'

module reset
module load ${_module_list}

PYVENV_PATH=$wrkspace/$cluster_name/share/$shortname

source \$PYVENV_PATH/bin/activate

python \\
  -m ipykernel_launcher \\
  -f \${CONNFILE}

echo '========================================================='
" > $kernel_start_file

		if [[ -e "$kernel_start_file" ]]; then
			green_text "$kernel_start_file succesfully created"
		else
			red_text "$kernel_start_file could not be created"
		fi
	}

	function create_kernel_json {
		shortname="$1"
		_name="$2"

		if [[ ! -e $wrkspace/$cluster_name/opt/start-${shortname}-kernel.sh ]]; then
			red_text "!!! $wrkspace/$cluster_name/opt/start-${shortname}-kernel.sh not found !!!"
		fi

		echo "{
			\"display_name\": \"$_name\",
			\"argv\": [
				\"$wrkspace/$cluster_name/opt/start-${shortname}-kernel.sh\",
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

	current_cluster_load=$(echo "$CONFIG_JSON" | ./jq -r --arg cluster_name "$cluster_name" '.modules_by_cluster[$cluster_name]')

	current_load="$current_cluster_load"

	green_reset_line "➤Loading modules for $cluster_name..."

	module_load "$current_load"

	green_text "\nPython version: $(python3 --version)"

	echo "$CONFIG_JSON" | ./jq -c '.kernels | to_entries[]' | while IFS= read -r kernel_entry; do
		kernel_key=$(echo "$kernel_entry" | ./jq -r '.key')
		kernel_name=$(echo "$kernel_entry" | ./jq -r '.value.name')
		kernel_tests=$(echo "$kernel_entry" | ./jq -r '.value.tests | join(" ")')
		kernel_ml_dependencies=$(echo "$kernel_entry" | ./jq -r '.value.module_load | join(" ")')
		kernel_pip_dependencies=$(echo "$kernel_entry" | ./jq -r '.value.pip_dependencies | join(" ")' 2>/dev/null)
		test_script=$(echo "$kernel_entry" | ./jq -r '.value.test_script | join(" ")' 2>/dev/null)

		kernel_dir="$wrkspace/$cluster_name/share/$kernel_key"

		yellow_text "\n➤Installing kernel $kernel_key ($kernel_name)...\n"

		for ml_dependency_group in $kernel_ml_dependencies; do
			module_load $ml_dependency_group
		done

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

		green_reset_line "➤Upgrading pip in $kernel_dir"
		pip install --upgrade pip 2>/dev/null >/dev/null
		if [[ $? -eq 0 ]]; then
			green_reset_line "✅Pip upgraded $kernel_dir"
		else
			red_reset_line "❌Pip upgraded $kernel_dir"
		fi

		FROZEN=$(pip list --format=freeze)

		for pip_dependency_group in $kernel_pip_dependencies; do
			dependency_value=$(echo "$CONFIG_JSON" | ./jq -r ".pip_module_groups[\"$pip_dependency_group\"]")
			if [[ $? -eq 0 ]]; then
				# Check for pip_complex for the current cluster
				pip_complex_value=$(echo "$CONFIG_JSON" | ./jq -r ".pip_module_groups[\"$pip_dependency_group\"].pip_complex[\"$cluster_name\"]" 2>/dev/null)
				if [[ $? -eq 0 ]]; then
					if [[ "$pip_complex_value" != "null" ]]; then
						ppip_complex "$pip_complex_value"
					else
						true
						#red_reset_line "❌Could not find .pip_module_groups[$pip_dependency_group].pip_complex[$cluster_name]}"
					fi
				else
					ppip "$dependency_value"
					#red_reset_line "❌Could not find .pip_module_groups[$pip_dependency_group].pip_complex[$cluster_name]}"
				fi
			else
				red_reset_line "❌Could not find .pip_module_groups[$pip_dependency_group]"
			fi
			echo ""
		done

		create_start_kernel_sh "$kernel_key" "$kernel_name" "$current_load $kernel_ml_dependencies"
		create_kernel_json "$kernel_key" "$kernel_name"

		# Iterate through tests
		for kernel_test in $kernel_tests; do
			eval "$kernel_test"
			if [[ $? -ne 0 ]]; then
				red_text "\n$kernel_key tests failed\n"
			fi
		done

		if [[ -n $test_script ]]; then
			eval "$test_script"
			exit_code=$?
			if [[ $exit_code -eq 0 ]]; then
				green_text "Test for $kernel_key successful"
			else
				red "Test for $kernel_key failed with exit code $exit_code"
			fi
		fi

		deactivate
		echo ""
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
