# PyTorch-Kernel installer for HPC-systems with Lmod at the TU Dresden

This tools helps you to install the dependencies of Jupyter Notebooks on different partitions. It assumes that you have `lmod` available.

You can specify the install requirements with a simple JSON file.

# JSON-format

```
{
  "modules_by_cluster": {
    "barnard": "release/23.10",
    "alpha": "release/23.10 GCC/11.3.0 OpenMPI/4.1.4 Python/3.10.4",
    "romeo": "release/23.10 GCC/11.3.0 OpenMPI/4.1.4 Python/3.10.4"
  },
  "pip_module_groups": {
    "base_pks": "setuptools wheel ipykernel ipywidgets beautifulsoup4 scrapy nbformat==5.0.2 matplotlib plotly seaborn",
    "sci_pks": "ipykernel numpy scipy sympy pandarallel dask mpi4py ipyparallel netcdf4 xarray[complete]",
    "ml_libs": "pybrain ray theano scikit-learn nltk",
    "tensorflow": "tensorflow==2.17.0",
    "torchvision_torchaudio": {
      "pip_complex": {
	"alpha": "torchvision torchaudio",
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
      "module_load": ["TensorFlow/2.11.0-CUDA-11.7.0"],
      "pip_dependencies": ["base_pks", "sci_pks", "ml_libs"],
      "check_libs": "bs4 scrapy matplotlib plotly seaborn numpy scipy sympy dask mpi4py ipyparallel netCDF4 sklearn nltk tensorflow",
      "test_script": "true"
    },
    "pytorch": {
      "name": "PyTorch (Machine Learning)",
      "module_load": ["PyTorch/1.13.1"],
      "pip_dependencies": ["base_pks", "sci_pks", "ml_libs", "torchvision_torchaudio"],
      "check_libs": "bs4 scrapy matplotlib plotly seaborn numpy scipy sympy dask mpi4py ipyparallel netCDF4 sklearn nltk torch torchvision torchaudio",
      "test_script": "true"
    }
  }
}
```

## JSON-Format explanation:

### `modules_by_cluster`:

If you have different clusters, for each one, for example, depending on the CPU architecture, you need different modules. 

`modules_by_cluster` allows you to specify a list (as a string) of values that will be loaded via `ml $LOAD_STRING`. The Cluster chosen will be determined by `basename -s .hpc.tu-dresden.de $(hostname -d)`.

### `pip_module_groups`:

This allows you to specify groups of modules that belong together, e.g. the `ml_libs` subkey, which contains all kinds of machine learning libraries for the Kernel. This allows you to write less code, when you want to install many kernels and most of them have similiar groups of modules that are required. They can later be used by specifying `pip_dependencies` in the `kernels`-subkey for each single kernel.

If the value is a simple string, it will be the same for all clusters. If it is a dictionary, it will use the dictionary keys to check which server you are on, and install the dependencies for that server and not the others. It also allows more complex pip commands, like the index-url-command. If a key for a cluster is missing, nothing will be install in this step, though this doesn't stop the kernel itself from being install when it works.

### `kernels`:

A list of kernels to be installed. Each kernel has a key that acts as it's internal name (e.g. tensorflow). It also has a 'nice' name that is given as a parameter to the key, e.g. "TensorFlow (Machine Learning)". 

`module_load` specifies modules that should be loaded, but are inconvienent to define in the `modules_by_cluster`. This is not a module or pip-group, but rather, a list (string) of ml modules to be loaded before pip is used.

### `pip_dependencies`:

References to a key of the `pip_module_groups`. Installs those modules in the order of the elements in the `pip_module_groups`.

### `check_libs`:

A list of libraries that need to be loadable in Python for the build to be called a success.

### `test_script`:

A bash script that is executed. If it exits with anything other than exit-code 0, it will count as failed.
