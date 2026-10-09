#!/usr/bin/env bash
# Usage: branch-freshness.sh <repo-path>...
# For each repo: origin default branch, current branch, commits behind origin default, uncommitted files.
set -uo pipefail
printf '%-28s %-10s %-44s %7s %6s\n' REPO DEFAULT CURRENT BEHIND DIRTY
for repo in "$@"; do
  name=$(basename "$repo")
  if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    printf '%-28s %s\n' "$name" "not a git repo"; continue
  fi
  git -C "$repo" fetch --quiet origin 2>/dev/null || echo "warn: fetch failed for $name" >&2
  default=$(git -C "$repo" ls-remote --symref origin HEAD 2>/dev/null | awk '/^ref:/{sub("refs/heads/","",$2); print $2; exit}')
  if [ -z "$default" ]; then
    for b in develop main master; do
      git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$b" && { default=$b; break; }
    done
  fi
  current=$(git -C "$repo" branch --show-current); current=${current:-"(detached)"}
  behind=$(git -C "$repo" rev-list --count "HEAD..origin/$default" 2>/dev/null || echo "?")
  dirty=$(git -C "$repo" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  printf '%-28s %-10s %-44s %7s %6s\n' "$name" "$default" "${current:0:44}" "$behind" "$dirty"
done
