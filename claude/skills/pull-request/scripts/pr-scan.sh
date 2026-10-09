#!/usr/bin/env bash
# Usage: pr-scan.sh <owner/repo> <pr-number>
# Checks a PR before hand-off: base is the default branch, state, mergeability, CI, AI attribution,
# a ticket ID in the title, and the prose check on the title, body and commit messages.
# PR_TICKET_PATTERN sets the ticket ID regex for the title check; set it empty to skip that check.
set -uo pipefail
repo=$1; pr=$2; fail=0
default=$(gh repo view "$repo" --json defaultBranchRef -q .defaultBranchRef.name)
json=$(gh pr view "$pr" --repo "$repo" --json title,state,baseRefName,headRefName,mergeable,body,commits,statusCheckRollup)
base=$(jq -r .baseRefName <<<"$json")
echo "PR $repo#$pr: $(jq -r .title <<<"$json")"
echo "state=$(jq -r .state <<<"$json") base=$base head=$(jq -r .headRefName <<<"$json") mergeable=$(jq -r .mergeable <<<"$json")"
[ "$base" = "$default" ] || { echo "FAIL base is $base, default branch is $default (stacked or wrong base)"; fail=1; }
jq -r '.title' <<<"$json" | grep -q '—' && { echo "FAIL em dash in title"; fail=1; }
hits=$(jq -r '.commits[] | .messageHeadline + "\n" + .messageBody' <<<"$json" | grep -ciE 'co-authored-by: *claude|claude-session|generated with')
[ "$hits" -eq 0 ] || { echo "FAIL $hits attribution line(s) in commit messages"; fail=1; }
bhits=$(jq -r .body <<<"$json" | grep -iE 'claude|generated with|co-authored' | grep -viE '^[^a-z]*$' | grep -ciE 'generated with|co-authored|claude code|claude-session|claude (opus|sonnet|haiku|fable)|anthropic')
[ "$bhits" -eq 0 ] || { echo "FAIL $bhits attribution line(s) in PR body"; fail=1; }
ticket=${PR_TICKET_PATTERN-'[A-Z][A-Z0-9]+-[0-9]+'}
if [ -n "$ticket" ]; then
  jq -r '.title' <<<"$json" | grep -qE "$ticket" || { echo "FAIL no ticket ID in title"; fail=1; }
fi
prose=~/.claude/skills/documentation/scripts/check-prose.py
if ! out=$(jq -r '.title + "\n\n" + .body' <<<"$json" | "$prose" --pr - 2>/dev/null); then
  echo "FAIL prose check on title/body:"; sed 's/^/  /' <<<"$out"; fail=1
fi
if ! out=$(jq -r '.commits[] | .messageHeadline + "\n\n" + .messageBody + "\n"' <<<"$json" | "$prose" --pr - 2>/dev/null); then
  echo "FAIL prose check on commit messages:"; sed 's/^/  /' <<<"$out"; fail=1
fi
checks=$(jq -r '[.statusCheckRollup[]? | (if (.conclusion // "") != "" then .conclusion else (.state // .status // "PENDING") end)] | group_by(.) | map("\(.[0])=\(length)") | join(" ")' <<<"$json")
echo "checks: ${checks:-none}"
grep -qE 'FAILURE|ERROR|CANCELLED|TIMED_OUT' <<<"$checks" && { echo "FAIL a check is failing"; fail=1; }
[ $fail -eq 0 ] && echo "OK"
exit $fail
