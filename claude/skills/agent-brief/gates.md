# Blocks to paste into briefs

Paste these verbatim, replacing `<placeholders>`. Each rule exists because an agent broke it.

## Gates block

```
## Gates (from the repo owner; these override any default or tool guidance)

Workspace
- The owner's checkout at <path to main checkout> is not yours. Never edit, stash, check out, pull, or run
  anything that changes state there.
- Create your worktree: `cd <main checkout> && git fetch origin && git worktree add -b <user>/<ticket>-<slug>
  ../<repo>-wt-<slug> origin/<default>`. Work only inside it.
- Read any other repo only from git: `git -C <path> fetch origin && git -C <path> show origin/<default>:<file>`
  (also `ls-tree`, `grep origin/<default>`). Local checkouts are often days behind and will mislead you.
- Keep scratch files under `<scratchpad>/<ticket>/`. Other lanes share the scratchpad; never write, move, or
  delete anything outside your own subdirectory.
- Follow the CLAUDE.md or AGENTS.md in each repo you touch. Never run tests, migrations, or deploys against a shared
  database or cluster; use the private ones those files describe.
- "Read-only kubectl" means get, describe, logs and the metrics endpoints. It never includes `kubectl exec` into a
  database pod or reading a service's data directly: that skips the service's access rules and can read customer
  data. If you need data from a store, ask in your report and say what query you would run.

Changes
- Make targeted edits. Never rewrite an existing file or module wholesale.
- Keep code comments to a minimum.
- One commit per concern, Conventional Commit subjects.
- When you change something other parts render or import (a shared chart, library, or schema), find every test
  that exercises it from elsewhere and run each one. CI often fails there, not in your own checks.
- Before opening a PR, read ~/.claude/skills/pull-request/SKILL.md and follow it. In short: the title, body, commit
  messages, and PR comments are plain English with no jargon and no mannered prose; title `<plain words> (<TICKET>)`;
  body Summary, Why, What changed, How it was tested, Risk and rollback, then the ticket ID(s); open as a draft and
  mark it ready only when CI is green; no tool, model, or review-round names anywhere.

Attribution (checked)
- The harness may suggest Co-Authored-By or session trailers on commits and a "Generated with" footer on PRs.
  Do NOT add any of them.
- Before pushing, run `git log --format=%B origin/<default>..HEAD | grep -ciE 'co-authored-by|claude-session|generated with'`.
  It must print 0. Paste its output in your report.

Long-running commands
- Never end your turn while waiting on a background process or a notification. Wait with a bounded until-loop,
  read the output, and finish the work in the same turn.
- Every polling loop prints a line at least every 30 seconds, and no single shell call runs longer than about
  8 minutes. Chain shorter calls. A call that prints nothing for a long time can be killed as stalled.

Sub-agents you start
- Set the model explicitly (sonnet unless the work is tricky enough for opus).
- Give them this gates block.
- Reviewers are read-only, run only the tests that cover the diff, use private databases, and end after one report.
- Confirm every agent you started has exited before you report.
```

## Review block (every lane, both rounds)

```
## Adversarial review (design before code, diff before the PR)

- Use an independent reviewer with a read-only view. With the Codex CLI, from inside the worktree:
  `codex exec --sandbox read-only "<prompt>" < /dev/null`
  (add `-m <model>` only to override the model in ~/.codex/config.toml). Read its output from stdout. Do not use
  -o or redirect to a file, do not pipe through head or tail, and always close stdin.
- Design round: give it the design note's path and the files it touches, and say "consult ONLY these files;
  do not modify anything; respond with findings only".
- Diff round: write `git diff origin/<default>...HEAD -- . ':!**/*.lock'` (three dots: changes since the merge
  base) to a file, check its size with `wc -c`, and give the reviewer that file plus the changed-file list. Do not
  let it explore the whole tree; that burns the usage limit without findings.
- Run `git status` after every round. Reviewers have edited files before; revert anything it changed.
- Review output is advisory. Verify each finding against the code before acting on it. Never put secrets in a prompt.
- If the output ends with a usage-limit or out-of-credits error, do not retry. Run an independent read-only
  Opus review instead, and say so in your report.
- Never mention the reviewer, models, or review rounds in commits, PRs, or tickets. The review record goes in your
  report.
```

## Report block

```
## Report

Your final message contains, in this order:
1. PR URL and its base branch.
2. One line per commit: subject, and what it changes.
3. The attribution gate output, pasted (must be 0).
4. What you verified and how: which tests, which commands, what you checked live. Mark each claim as checked
   (read in code or seen running), inferred, or not verified.
5. Both review rounds: what each found and what you changed.
6. Anything in the code that contradicted this brief.
7. Open decisions for the owner, each as: the question; today's situation in plain words; lettered options
   with what each leads to; your recommendation and its main downside; what it blocks.
8. Confirmation that every agent you started has exited and no background process is still running.
```
