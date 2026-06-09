#!/usr/bin/env bash
# Heuristic: prefer Python venv from environment of the pane's cwd
P="${1:-$PWD}"
# If .venv exists in tree, print name
if [[ -d "$P/.venv" ]]; then
  echo "(venv)"
  exit 0
fi
# pyenv local
if command -v pyenv >/dev/null 2>&1; then
  V=$(cd "$P" && pyenv version-name 2>/dev/null)
  if [[ -n "$V" ]]; then
    echo "({$V})" | sed 's/{//;s/}//'
    exit 0
  fi
fi
# If dir contains poetry.lock
if [[ -f "$P/poetry.lock" ]]; then
  echo "(poetry)"
  exit 0
fi
# If dir has requirements.txt
if [[ -f "$P/requirements.txt" ]]; then
  echo "(py)"
  exit 0
fi
