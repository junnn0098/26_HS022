#!/usr/bin/env bash
set -euo pipefail

python_bin="${RUVIEW_PYTHON:-python3}"
user_site="$($python_bin -c 'import site; print(site.getusersitepackages())')"
nvidia_lib="${RUVIEW_NVIDIA_LIB_DIR:-$user_site/nvidia/cu12/lib}"

library_paths=()
if [[ -d "$nvidia_lib" ]]; then
  library_paths+=("$nvidia_lib")
fi
if [[ -d /usr/local/cuda/lib64 ]]; then
  library_paths+=(/usr/local/cuda/lib64)
fi
if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
  library_paths+=("$LD_LIBRARY_PATH")
fi
if (( ${#library_paths[@]} > 0 )); then
  export LD_LIBRARY_PATH="$(IFS=:; echo "${library_paths[*]}")"
fi

exec "$python_bin" "$@"
