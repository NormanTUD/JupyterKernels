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

	DEBUG=0
	DISABLE_TAURUS_CHECK=0
	#default_workspace='/software/util/JupyterLab'
	default_workspace='/data/horse/ws/s4122485-jupyter_kernels'
	# Initialize variables
	CONFIG_JSON=""
	workspace=$default_workspace

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

	function debug {
		msg=$1
		if [[ $DEBUG -eq 1 ]]; then
			yellow_text "\n$msg\n"
		fi
	}

	function debug_var_if_empty {
		varname=$1
		if [[ $DEBUG -eq 1 ]]; then
			var=$(eval "echo \$$varname")
			if [[ -z $var ]]; then
				debug "Variable \$$varname was emty when it shouldn't be!"
			fi
		fi
	}

	function _help {
		ec=$1
		echo "build_kernels.sh - Build Jupyter Kernels from JSON definition files"
		echo "Parameters:"
		echo "path/to/config.json                            Path to your config file"
		echo "path/to/workdir                                Path to work dir"
		echo "--debug                                        Show debug output"
		echo "--disable_taurus_check                         Allow to run on other systems than taurus"
		echo "--help                                         This help"

		exit $ec
	}

	# Process parameters
	for param in "$@"; do
		if [[ "$param" == "--debug" ]]; then
			DEBUG=1
		elif [[ "$param" == "--help" ]]; then
			_help 0
		elif [[ "$param" == "--disable_taurus_check" ]]; then
			DISABLE_TAURUS_CHECK=1
		elif is_json_file "$param"; then
			CONFIG_JSON=$(cat "$param")
		else
			workspace="$param"
		fi
	done



	FROZEN=""

	ORIGINAL_PWD=$(pwd)

	mkdir -p $workspace 2>/dev/null || {
		red_text "Cannot create workspace $workspace\n"
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

		LOGFILE="$(echo ${TO_INSTALL} | md5sum | sed -e 's# .*##')_pip.log"

		pip3 --log "$LOGFILE" -qqq install $TO_INSTALL 2>/dev/null >/dev/null || {
			red_text "\n❌Could not install $TO_INSTALL. Check $LOGFILE for more details\n"
			exit 30
		}

		rm "$LOGFILE"

		FROZEN=$(pip list --format=freeze)
		green_reset_line "✅Module $TO_INSTALL installed."
	}

	function ppip {
		TO_INSTALL="$1"

		i=0
		MAXMODNR=$(echo "$TO_INSTALL" | sed -e 's#\s#\n#g' | wc -l)
		PBAR=$(generate_progress_bar $i $MAXMODNR)
		green_reset_line "$PBAR➤Installing $TO_INSTALL"
		pip3 -qqq --upgrade pip 2>/dev/null >/dev/null

		for ELEM in $(echo "$TO_INSTALL"); do
			if ! echo "$FROZEN" | grep "$ELEM" 2>/dev/null >/dev/null; then
				PBAR=$(generate_progress_bar $i $MAXMODNR)
				green_reset_line "$PBAR➤Installing $ELEM ($(($i+1))/$MAXMODNR)"
				pip3 --log "${ELEM}_pip.log" -qqq install $ELEM 2>/dev/null >/dev/null || {
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
		failed=0

		for l in $MODS; do
			if [[ $failed -gt 0 ]]; then
				yellow_text "\nSkipping $l because an earlier test has already failed\n"
			else
				green_reset_line "Trying to import $l..."

				echo "import $l" | python3
				exit_code=$?

				if [[ $exit_code -ne 0 ]]; then
					red_text "\n-> echo 'import $l' | python3 <- failed\n"

					failed=$(($failed+1))
				fi
			fi
		done

		echo ""

		return $failed
	}

	function create_start_kernel_sh {
		shortname="$1"
		_name="$2"
		_module_list="$3"
		_modules_list="$4"

		opt_dir="$workspace/$cluster_name/opt/"

		opt_dir=$(echo "$opt_dir" | sed -e 's#//#/#g')

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

PYVENV_PATH=$workspace/$cluster_name/share/$shortname

source \$PYVENV_PATH/bin/activate

python \\
  -m ipykernel_launcher \\
  -f \${CONNFILE}

echo '========================================================='
" > $kernel_start_file

		if [[ -e "$kernel_start_file" ]]; then
			green_text "$kernel_start_file successfully created"
		else
			red_text "$kernel_start_file could not be created"
		fi
	}

	function create_kernel_json {
		shortname="$1"
		_name="$2"

		if [[ ! -e $workspace/$cluster_name/opt/start-${shortname}-kernel.sh ]]; then
			red_text "!!! $workspace/$cluster_name/opt/start-${shortname}-kernel.sh not found !!!"
		fi

		echo "{
			\"display_name\": \"$_name\",
			\"argv\": [
				\"$workspace/$cluster_name/opt/start-${shortname}-kernel.sh\",
				\"{connection_file}\"
			],
			\"env\": {},
			\"language\": \"python\",
			\"metadata\": {
				\"debugger\": true
			}
		}" > $ORIGINAL_PWD/kernel_${shortname}.json
	}

	set -e

	if [[ $DISABLE_TAURUS_CHECK -eq 0 ]]; then
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
	fi

	cluster_name=$(basename -s .hpc.tu-dresden.de $hostnamed)
	green_text "Detected cluster: $cluster_name\n"


	if [[ ! -d "$workspace" ]]; then
		echo ""
		red_text "workspace $workspace cannot be found. Cannot continue.\n"
		exit 6
	fi

	if [[ ! -w "$workspace" ]]; then
		echo ""
		red_text "workspace $workspace is not writable. Cannot continue.\n"
		exit 7
	fi

	if command -v module 2>/dev/null >/dev/null; then
		green_reset_line "Resetting modules..."

		module reset >/dev/null 2>/dev/null || {
			red_text "\nFailed to reset modules\n"
			exit 4
		}
		green_reset_line "Modules resetted"
	else
		yellow_text "module could not be found. Is lmod installed?"
	fi



	if command -v module 2>/dev/null >/dev/null; then
		current_cluster_load=$(echo "$CONFIG_JSON" | ./jq -r --arg cluster_name "$cluster_name" '.modules_by_cluster[$cluster_name]' 2>/dev/null)
		debug_var_if_empty "current_cluster_load"
		current_load="$current_cluster_load"
		green_reset_line "➤Loading modules for $cluster_name..."

		module_load "$current_load"
	fi

	green_text "\nPython version: $(python3 --version)"

	kernel_entries=$(echo "$CONFIG_JSON" | ./jq -c '.kernels | to_entries[]')

	echo "$kernel_entries" | while IFS= read -r kernel_entry; do
		set +e
		kernel_key=$(echo "$kernel_entry" | ./jq -r '.key' 2>/dev/null)
		kernel_name=$(echo "$kernel_entry" | ./jq -r '.value.name' 2>/dev/null)
		kernel_ml_dependencies=$(echo "$kernel_entry" | ./jq -r '.value.module_load | join(" ")' 2>/dev/null)
		kernel_modules_load_by_cluster_dependencies=$(echo "$kernel_entry" | ./jq -r ".value.modules_load[\"$cluster_name\"]" 2>/dev/null) 
		kernel_pip_dependencies=$(echo "$kernel_entry" | ./jq -r '.value.pip_dependencies | join(" ")' 2>/dev/null)
		kernel_check_libs=$(echo "$kernel_entry" | ./jq -r '.value.check_libs' 2>/dev/null)
		kernel_test_script=$(echo "$kernel_entry" | ./jq -r '.value.test_script' 2>/dev/null)
		set -e

		debug_var_if_empty "kernel_key"
		debug_var_if_empty "kernel_name"
		debug_var_if_empty "kernel_ml_dependencies"
		debug_var_if_empty "kernel_modules_load_by_cluster_dependencies"
		debug_var_if_empty "kernel_pip_dependencies"
		debug_var_if_empty "kernel_check_libs"
		debug_var_if_empty "kernel_test_script"

		kernel_dir="$workspace/$cluster_name/share/$kernel_key"

		yellow_text "\n➤Installing kernel $kernel_key ($kernel_name) to $kernel_dir...\n"

		if [[ "$kernel_ml_dependencies" != "null" ]]; then
			for ml_dependency_group in $kernel_ml_dependencies; do
				module_load $ml_dependency_group
			done
		fi

		if [[ "$kernel_modules_load_by_cluster_dependencies" != "null" ]]; then
			for ml_dependency_group in $kernel_modules_load_by_cluster_dependencies; do
				module_load $ml_dependency_group
			done
		fi

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
			dependency_value=$(echo "$CONFIG_JSON" | ./jq -r ".pip_module_groups[\"$pip_dependency_group\"]" 2>/dev/null)
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

		create_start_kernel_sh "$kernel_key" "$kernel_name" "$current_load" "$kernel_ml_dependencies" "$kernel_modules_load_by_cluster_dependencies"
		create_kernel_json "$kernel_key" "$kernel_name"

		if [[ -n $kernel_check_libs ]]; then
			check_libs "$kernel_check_libs" || {
				echo "Failed checking libs..."
				exit 199
			}
		else
			yellow_text "No check_libs for $kernel_key"
		fi

		if [[ -n $kernel_test_script ]]; then
			yellow_text "Checking kernel_test_script '$kernel_test_script'...\n"
			eval "$kernel_test_script"
			exit_code=$?
			if [[ $exit_code -eq 0 ]]; then
				green_text "Testscript '$kernel_test_script' for $kernel_key successful\n"
			else
				red_text "Testscript '$kernel_test_script' for $kernel_key failed with exit code $exit_code\n"
			fi
		else
			yellow_text "No kernel_test_script found (\$kernel_test_script: $kernel_test_script)...\n"
		fi

		deactivate
		echo ""
	done

	exit
}
