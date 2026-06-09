#!/usr/bin/env bash
# Usage: git_branch.sh <path>
P="${1:-$PWD}"
BR=$(git -C "$P" rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ -n "$BR" ]]; then
  echo " ${BR}"
fi
