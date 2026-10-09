---
name: pull-request
description: A standard for pull requests, from branch to hand-off. Use it whenever you open, update, rebase, or hand over a PR, write or rewrite a PR title, body, commit message, or PR comment, or when the user says "open the PR", "open a draft PR", "rewrite the PR description", "it needs a rebase", "it has a merge conflict", or "the PR has a failing CI job". Covers branching, PR shape, checks before opening, plain-English title and body, CI, conflicts, and hand-off.
user_invocable: true
---

# Pull requests

A PR is read twice: by a reviewer who has not seen the work, and months later by an engineer trying to learn why the code is this way. Write every part of it for them.

## Writing: plain English, no jargon, no mannered prose

This applies to the title, the body, every commit message, and every PR comment or reply to a review comment.

- **Plain English.** Short sentences, one idea each, active voice. Say what changed and what someone will notice.
- **No jargon.** The reader is an engineer new to this work. Standard industry terms are fine. Define every project term in the sentence where it first appears. No planning words (lane, slice, round, gate, seam, spike, fold, phase names, workstream numbers) and no internal codes (F3, I7, PR-A).
- **No mannered prose.** None of the patterns in `~/.claude/skills/documentation/references/mannered-prose.md`. Read it before writing the body. No em dashes.
- **Nothing about how the work was made.** No AI, models, reviewers, or review rounds. No attribution trailers or footers. Do not name the person who made a decision ("Alex decided"). State the decision itself.
- **Check it.** Run the prose check on the body and the commit messages before opening, and again after every edit:

  ```
  ~/.claude/skills/documentation/scripts/check-prose.py --pr body.md
  git log --format=%B origin/<default>..HEAD | ~/.claude/skills/documentation/scripts/check-prose.py --pr -
  ```

## 1. Start

- Find or file the ticket first (`linear-ticket` skill, or the tracker the repo uses).
- Get the default branch from GitHub, not from the local clone: `git ls-remote --symref origin HEAD`. The local `origin/HEAD` pointer is set at clone time and goes stale when the default branch changes.
- In repos with two long-lived branches (for example `develop` for work and `main` for releases), PRs go to the working branch. The release branch changes only through the release process.
- Work in a worktree off `origin/<default>`: `git worktree add -b <user>/<ticket>-<slug> ../<repo>-wt-<slug> origin/<default>`. Never branch from a local branch that may be stale.

## 2. Shape

- One concern per PR, and one commit per concern within it, with Conventional Commit subjects (`fix:`, `feat:`, `docs:`).
- Split into separate PRs where a combined one tends to cause trouble:
  - A change to shared configuration (an identity provider's settings, a feature flag store) and the application change that depends on it. The dependent PR merges after the first one is live.
  - A new required status check ships in the same PR as the CI job that produces it, never before it.
- Never stack. Open every PR against the default branch. When one depends on another, say "Depends on #N" in the first line of the summary, and keep it in draft until #N merges.
- Open as a draft. Mark it ready only when step 5 passes. A PR whose design is still being decided stays in draft until the decision is made.

## 3. Before opening

1. Rebase onto the latest default branch: `git fetch origin && git rebase origin/<default>`.
2. Run the checks the repo's AGENTS.md or CLAUDE.md lists. After changing something other parts render or import (a shared chart, library, or schema), also run the tests that exercise it from elsewhere.
3. Run the prose check on any Markdown the branch changes: `check-prose.py --diff origin/<default>`.
4. Attribution: `git log --format=%B origin/<default>..HEAD | grep -ciE 'co-authored-by|claude-session|generated with'` must print 0.
5. Secrets: no tokens, keys, passwords, or kubeconfigs in the diff or the body.

## 4. Title and body

Title: `<what the PR does, in plain words> (<TICKET>)`. Example: `Retry failed webhook deliveries with backoff (ENG-1234)`.

Body, unless the repo has a `PULL_REQUEST_TEMPLATE` (then fill its sections by these rules):

```markdown
## Summary
One paragraph a newcomer can follow: what this PR does and the effect someone will notice.
"Depends on #N" goes first, when it applies.

## Why
The problem, concretely: the error people hit, the manual step this removes, the request that failed.

## What changed
- Area A: what changed in it and why it had to.
- Area B: ...
(Group by area of the system, not file by file. The diff already lists the files.)

## How it was tested
The commands run and what they showed. Tests added and what each one proves.
Manual or live checks, with the environment they ran in.

## Risk and rollback
What could break, who would notice, and how to undo it.

ENG-1234
```

- Add a mermaid diagram when the PR changes how components talk to each other or the order things happen in.
- Add a docs line where the repo's agent instructions require one ("Docs delta: ...").
- Name a file or symbol only when the reviewer needs to look at it specifically.

## 5. Before saying it is ready

1. Run `~/.claude/skills/pull-request/scripts/pr-scan.sh <owner/repo> <n>`. It checks the base branch, mergeability, CI, attribution in commits and body, a ticket ID in the title (`PR_TICKET_PATTERN` sets the pattern; empty skips it), and the prose check on the title, body, and commit messages.
2. Wait for CI with a bounded loop that prints a line at least every 30 seconds, for up to about 15 minutes. When a check fails, read its log, fix it, push, and wait again. If CI is still running at the limit, hand the PR over as "CI pending" and say which checks are running.
3. Mark it ready (`gh pr ready <n>`) only once CI is green and the scan passes.
4. Hand it over using the `status-report` layout: one line per PR saying what it does, and the merge order with the reason for it.

## 6. Conflicts and rebases

- After any merge, check every open PR from this effort: `gh pr view <n> --json mergeable,baseRefName`. When one shows `CONFLICTING`, rebase it onto the default branch in its worktree, rerun step 3, and push with `git push --force-with-lease`. Do this unasked, only on branches you opened, never on the user's or anyone else's.
- When a rebase conflict needs a judgement call (both sides changed the same behaviour), stop and put it to the user as a decision instead of choosing.
- When the user reports "N needs a rebase", do it at once and say what conflicted and how it was resolved, in one line.

## 7. Rewriting a body

When asked to rewrite a PR description, write it for the reader the user names, or for an engineer new to the work by default. Keep every ticket ID. Apply the writing rules above, run the prose check, and update it in place: `gh pr edit <n> --repo <owner/repo> --body-file body.md`. Show the new summary paragraph in the reply.
