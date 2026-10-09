---
name: checkpoint
description: Write a checkpoint of a long-running effort so it survives /compact or a fresh session. Use it when the user types /checkpoint, asks for a handoff, a HANDOFF.md, "a prompt to start a new agent", or a summary of work done, work left, and what can be dispatched next, or before compacting. Updates the effort's memory note, writes a handoff file with a kickoff prompt outside every repo, and prints a short summary.
user_invocable: true
---

# Checkpoint

A checkpoint replaces typing a long `/compact <instructions>` every time. Claude Code has no setting that makes compaction instructions permanent, so the summary is written first, and a plain `/compact` then carries it forward because it is already in the conversation.

## 1. Re-check the state

Do not write from memory of the session.

- PRs in play: `gh pr view` for each, covering state, base, mergeability, and checks.
- Repos: `~/.claude/skills/agent-brief/scripts/branch-freshness.sh <repos>` and `git worktree list` for each.
- Agents and workflows this session started: which are running, finished, or failed.
- The tracker: the effort's open tickets and their states.

## 2. Write the handoff file

Path: `${HANDOFF_DIR:-$HOME/handoffs}/<effort-slug>.md`. Create the folder if it is missing. Never write a handoff inside a repo or worktree, where it can be committed by accident. If one exists for this effort, update it in place.

Follow the plain-English rules in `~/.claude/skills/documentation/SKILL.md`. Ticket IDs and PR numbers are fine here. Sections, in order:

```markdown
# <Effort name>: handoff

Updated <YYYY-MM-DD HH:MM TZ>.

## Goal
What the effort is for and what "done" looks like, in two or three sentences.

## Where things stand
Two or three sentences measured against the goal.

## Done
One line per result, written as the effect, with PR and ticket: "Failed webhooks now retry (api #88, ENG-2401)."
Group by area. Since the start of the effort, or since the last checkpoint if this file existed.

## Open PRs and merge order
Numbered, in the order to merge, with the reason for the order and any retarget step.

## Open decisions
The session-wide numbers, each in short form: question, lettered options, recommendation.

## Next work that can be dispatched
One line each: ticket, what it does, what blocks it (or "nothing"), and the suggested model.

## Branches and worktrees
| Repo | Branch | Worktree | State |
State is one of: has open PR #N, merged (safe to remove), uncommitted work, or stale.

## Traps
Things that went wrong in this effort and how to avoid them, one line each.

## Check the state yourself
The exact commands that show the current state: gh, git, kubectl, test commands.

## Kickoff prompt
(See below.)
```

The kickoff prompt is a fenced block a new session can paste as-is:

```
Read ~/handoffs/<effort-slug>.md in full before doing anything.
Load the agent-brief, status-report, and after-merge skills.
Run the commands under "Check the state yourself" and tell me what changed since the handoff was written.
Then <the next concrete step: the decision to ask for, or the lane to dispatch>.
```

Run `~/.claude/skills/documentation/scripts/check-prose.py --pr <file>` on the handoff and fix the hits.

## 3. Update memory

Update the effort's project memory note, or create one named `<effort>-status.md`. Write a dated snapshot of a few lines: where things stand, open PRs, next step, and the path to the handoff file. Replace the snapshot it supersedes rather than appending below it. Update the note's line in `MEMORY.md` with the date and a one-line hook.

## 4. Reply

At most ten lines:

- Where things stand, in one sentence.
- What needs the user: merges in order, and decision numbers.
- The handoff file path.
- "Run `/compact` now, or start a new session with the kickoff prompt in the handoff file."

## When to suggest one

Suggest a checkpoint in one line at the end of a reply when a batch of lanes has merged, a phase of the effort has finished, or the session has run one effort for many hours. Do not write it unasked.
