# Claude Code skills and preferences

This folder holds a set of Claude Code skills and a global `CLAUDE.md`. A skill is a folder with a `SKILL.md` that Claude Code loads when a request matches its description. `CLAUDE.md` holds standing preferences that apply to every session, and tells Claude when to load each skill.

| Skill | What it does |
|---|---|
| `documentation` | Plain-English rules for docs, ADRs, and onboarding pages: the default reader, diagrams, worked examples, and a prose check script. |
| `status-report` | A fixed layout for status and decision replies, with decisions numbered across a session. |
| `agent-brief` | How to brief sub-agents: checks before dispatch, a gates block to paste, review rounds, and checks when the agent reports back. |
| `pull-request` | Pull requests from branch to hand-off: shape, checks, title and body, CI, conflicts. |
| `after-merge` | What to do when PRs merge: confirm where they landed, fix stacked and conflicting PRs, tidy worktrees, propose the rollout. |
| `checkpoint` | Writes a handoff file and memory note so a long effort survives `/compact` or a new session. |
| `linear-ticket` | Filing, closing, and auditing Linear tickets in a fixed shape. |
| `env-parity` | Compares two environments of a GitOps deploy repo, from git and read-only from the clusters. |
| `codex-review` | Iterates a plan with the Codex CLI until it approves. |

## How bootstrap installs them

`bin/bootstrap.sh` links each skill folder to `~/.claude/skills/<name>`, and `CLAUDE.md` to `~/.claude/CLAUDE.md`. Because they are links, an edit made in any session lands in this repo, ready to commit.

If you already have a real folder or file at one of those paths, bootstrap keeps yours and prints a note. To replace yours with the repo version, run `ZEPH_CLAUDE_FORCE=1 ./bin/bootstrap.sh`, which first moves yours to `<name>.bak`.

## Settings

| Setting | Used by | What it does |
|---|---|---|
| `PROSE_TICKET_PREFIX` | `check-prose.py` | A regex for your tracker's ticket prefixes (for example `ENG\|OPS`), so only those are flagged in docs. |
| `PR_TICKET_PATTERN` | `pr-scan.sh` | The ticket ID pattern a PR title must contain. Set it empty to skip the check. |
| `HANDOFF_DIR` | `checkpoint` | Where handoff files go. The default is `~/handoffs`. |
| `CODEX_MODEL` | `codex-review` | A model to use instead of the one in `~/.codex/config.toml`. |

Set your Linear team and key in `CLAUDE.md`, where the comment marks the spot.
