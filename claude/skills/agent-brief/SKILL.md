---
name: agent-brief
description: How to dispatch sub-agents. Use it before every Agent-tool call or Workflow agent() that does real work (implementation, fixes, docs, design, investigation, review), and whenever the user says "dispatch", "send an agent", "kick off", "file it and dispatch", or "go ahead on the next lanes". Covers checks before dispatch, model choice, the brief layout, the gates block to paste, adversarial review rounds, and what to verify when the agent reports back.
user_invocable: true
---

# Dispatching sub-agents

A sub-agent cannot see `~/.claude/CLAUDE.md`, memory, or this conversation. It knows only what the brief says, and the harness pushes it toward defaults the user may have forbidden (attribution trailers, waiting on background processes). Write each brief as if the agent has never met the user.

## 1. Before dispatching

Run all four checks every time.

1. **Ticket.** Find or file the ticket. The brief carries its ID, and the PR title and body must include it.
2. **Branch freshness.** For every repo the agent will read or change, run `~/.claude/skills/agent-brief/scripts/branch-freshness.sh <repo-path>...`. Put the result in the brief. When any checkout is behind or on a feature branch, the brief says to read that repo only via `git show origin/<default>:<path>`.
3. **Interference.** Check for other worktrees, branches, open PRs, and running agents touching the same files, databases, or clusters (`git worktree list`, `gh pr list --search <path>`, this session's running agents). If anything overlaps, tell the user before dispatching and say what overlaps.
4. **Workflow or single agent.** If the request has three or more independent pieces, propose a Workflow to the user in one or two sentences (shape and rough cost) and wait for a yes, unless the user has already opted in.

## 2. Model

Set `model` on every call. Never omit it: omission silently inherits the session model.

- `sonnet`: the default, for well-specified implementation with clear acceptance criteria.
- `opus`: tricky work, such as concurrency, subtle algorithms, gnarly debugging, adversarial review, and design. Say in one line why Sonnet would not do.
- `haiku`: mechanical bulk work, such as renames, format conversion, and log triage.
- The most expensive tier: ask the user first, every time.

When the user names a model ("dispatch an Opus agent"), use it. If a Sonnet lane fails a gate or a post-check, redo it with Opus and say so.

## 3. The brief

Use these sections in this order. Keep the task-specific parts concrete: file paths, symbols, commands, and the exact acceptance check.

```
<One paragraph: what the agent is doing, for whom, and what done looks like.>

## Setup
Repo(s), branch name (<user>/<ticket>-<slug>), worktree path (<repo>-wt-<slug> next to the main checkout),
base (origin/<default>), and the branch-freshness table.

## Read first
The files, docs, ADRs, and skill files to read before starting, in order.
For docs work: ~/.claude/skills/documentation/SKILL.md and the matching reference file.

## Work items
Numbered. Each one names the files or symbols involved and its acceptance check.
Say what is out of scope, and name files another branch is changing.

## Decisions already made
Anything the user has ruled on that the agent must not reopen.

## Gates
<Paste the gates block from gates.md, with the placeholders filled in.>

## Report
<Paste the report block from gates.md.>
```

The brief itself follows the plain-English rules: say exactly what is meant, and define project terms the agent will not know.

## 4. Adversarial review

Every lane, including small and routine ones, runs two adversarial review rounds from `gates.md`: a design review before code and a diff review before the PR. Reviews keep catching real defects, and a lane that skips its design round tends to miss problems the diff round finds later. The reviewer is an independent model with a read-only view (for example the Codex CLI). When it is unavailable, the lane uses an independent read-only Opus review instead and says so.

## 5. When the agent reports

Before telling the user a lane is ready, check these yourself:

1. **Scan.** Run `~/.claude/skills/pull-request/scripts/pr-scan.sh <owner/repo> <pr>`, even when the agent pasted its own gate output. It checks attribution, the base branch, mergeability, CI, the ticket ID in the title, and the prose check on the title, body, and commit messages.
2. **Base and stack.** The PR targets the default branch. If it is stacked, retarget it to the default branch the moment its parent merges. Never hand the user a stack of ready PRs.
3. **Prose.** For any lane that touched Markdown, run `~/.claude/skills/documentation/scripts/check-prose.py --diff origin/<default>` in its worktree. Fix the hits or send the lane back.
4. **Claims.** Re-verify the one or two claims in the report that matter most, against code on the default branch or the live system.
5. **Review rounds.** Confirm the report shows both the design round and the diff round. Send the lane back if either was skipped.
6. **Nested agents.** Confirm that any agent the lane started has exited.

Then report to the user using the `status-report` skill. Pass the lane's decision cards along with the next session-wide numbers.
