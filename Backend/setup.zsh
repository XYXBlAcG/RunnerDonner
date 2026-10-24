#!/bin/zsh
set -eu
cd "${0:A:h}/.."
python_runtime="${RUNNER_PYTHON:-/opt/homebrew/opt/python@3.11/bin/python3.11}"
if [[ ! -x "$python_runtime" ]]; then
  print '请通过 RUNNER_PYTHON 指定 Python 3.11 的绝对路径。'
  exit 1
fi
if [[ ! -x Backend/.venv/bin/python ]]; then
  "$python_runtime" -m venv Backend/.venv
fi
Backend/.venv/bin/python -m pip install -r Backend/requirements-lock.txt
