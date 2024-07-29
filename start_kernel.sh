#!/bin/bash

CONNFILE=${1}

set -euo pipefail

echo "========================================================="
echo "Starting PyTorch..."

module reset
module load release/23.04
module load GCCcore/11.3.0
module load GCC/11.3.0
module load OpenMPI/4.1.4
module load Python/3.10.4

PYVENV_PATH=/software/util/JupyterLab/alpha/share/pytorch_v1

source $PYVENV_PATH/bin/activate

python \
  -m ipykernel_launcher \
  -f ${CONNFILE}

echo "========================================================="
