---
name: linear-ticket
description: Filing, updating, closing, and auditing Linear tickets. Use it when the user says "file it", "file them", "file a ticket", "open an issue", "pop an issue to track it", "close it if the work is complete", "make sure we're tracking this in Linear", or "are all statuses reflected in Linear", and before dispatching any lane that has no ticket yet.
user_invocable: true
---

# Linear tickets

Set your team and key once, in your global or project CLAUDE.md ("Linear team: Platform, key ENG"). Tickets link to the code through the GitHub integration: a PR whose title or body carries the ticket ID moves that ticket as the PR opens and merges.

## Before filing

- Search for an existing ticket first (`list_issues` with a query on the key words, in the effort's project). Update a match rather than filing a duplicate.
- Pick the project. Every ticket has one. Use the effort's project. If none fits, list the candidates for the user rather than leaving it blank.

## Shape of a ticket

Title: `<repo or area>: <what changes, in plain words>`. Example: `api: retry failed webhook deliveries with backoff`. No em dashes.

```markdown
## Problem
What is wrong or missing, who notices, and the evidence: the error, the command and its output, the PR or
log where it showed up. Plain English, with every project term defined.

## Scope
1. Numbered changes, each naming the repo and the files or components involved.

## Out of scope
- What this ticket deliberately does not cover, with the ticket that does, if one exists.

## Done when
- Checkable conditions: the test that passes, the command and its expected output, the live check.

## Related
Parent, blocked by, blocks, related tickets, and links to PRs, ADRs, and docs.
```

Fields:

- **Priority**: 1 Urgent (production or a customer-facing environment broken), 2 High (blocks the current effort), 3 Medium (default), 4 Low.
- **Label**: one of Bug, Feature, or Improvement, or the team's equivalents.
- **Relations**: set `parentId`, `blockedBy`, and `relatedTo` as real relations, not only as text in Related.
- **Assignee**: `me` when the work is being dispatched now. Otherwise leave it unassigned.
- **State**: Backlog or Todo when filed. In Progress when its lane is dispatched.

Follow the plain-English rules in `~/.claude/skills/documentation/SKILL.md`. Never mention AI, models, or review rounds in tickets or comments. Run `~/.claude/skills/documentation/scripts/check-prose.py --pr -` on the description before saving.

## Filing several at once

When the user says "file them", file each one and reply with a table: ticket ID, title, project, priority, and what it blocks. When "and dispatch" follows, dispatch with the `agent-brief` skill, using the new IDs in the briefs.

## Closing

- Set Done only when every "Done when" condition is met. Say in a comment which PR met it.
- When work merges but leaves part undone, keep the ticket open, and comment what remains or file a follow-up linked as related.
- Set Canceled with a one-line comment saying why: superseded by another ticket, no longer needed, or folded into another ticket.

## Audit

When the user asks whether Linear reflects reality, or after a batch of merges:

1. List the project's tickets that are not Done or Canceled.
2. For each, find its PRs (the ticket's links, plus `gh pr list --search <TICKET>` in the effort's repos).
3. Compare. Merged with "Done when" met but not Done; In Progress with no open PR and no running lane; and Done with an open PR are all mismatches.
4. Fix state mismatches the integration missed, and reply with a table of what changed and what needs the user's judgement.
