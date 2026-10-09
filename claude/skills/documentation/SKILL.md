---
name: documentation
description: A standard for engineering writing that people other than the user will read. Use it for repository docs (diataxis tutorials, how-to guides, explanation, reference), ADRs and design docs, and onboarding or explainer pages. Also use it when rewriting any of these to remove jargon or mannered prose, adding diagrams to a doc, or briefing a sub-agent to do docs work. Covers plain-English rules, the default reader, mermaid diagrams, worked examples, code references, and a prose check to run before hand-off.
user_invocable: true
---

# Documentation

Write for a reader who was not in the room. The reader cannot ask you what a word means, does not know the history of the work, and needs to finish the page able to do something or explain something.

## Pick the reference file for the task

| Task | Read |
|---|---|
| Pages in a repo's `docs/` folder | `references/diataxis.md` |
| A pull request title, body, or commit message | the `pull-request` skill |
| An ADR or design doc | `references/adr.md` |
| An onboarding or explainer page for engineers new to a system | `references/onboarding.md` |
| Any of the above, before the first draft | `references/mannered-prose.md` |

Read `references/mannered-prose.md` every time. It lists the patterns that a script cannot catch.

## The default reader

Unless the user names a different reader, write for a **new engineer**: technically capable, knows standard industry terms (HTTP, Kubernetes, Postgres, OAuth, a queue), and has never seen this project.

- Industry terms are fine without definition.
- Every project term (a service name, an internal concept, a team nickname for something) is defined in the sentence where it first appears on the page. Example: "The router, the service that picks which model answers a request, reads its rules from…". Define it again on each page; readers arrive from search, not from page one.
- After defining a term, use exactly that term every time. Never swap in a synonym for variety. A reader assumes a new word means a new thing.

When the user names the reader ("someone who knows the API but not its internals"), write for that reader instead, and still define anything they would not know.

When a product's name differs from the names of its repos, clusters, or services, call the product by its product name in prose, and keep identifiers (repo names, paths, cluster and namespace names, quoted config) exactly as they are, since changing them in a doc points the reader at something that does not exist.

## Write for the reader, not for yourself

These are the four ways a draft ends up written for its author.

1. **Process history.** Describe how the system works now, not how the work happened. Cut "first we tried X", "review found Y", "after several rounds". If a rejected approach matters, it goes in an ADR's options section.
2. **Working vocabulary.** Planning words never reach the reader: lane, slice, round, gate, seam, spike, workstream numbers, phase names, and similar. Ticket IDs and PR numbers stay out of repo docs, except in a references appendix. They do belong in PR titles and bodies, where they link the tracker.
3. **Self-justifying text.** No "This doc exists to…", no status banners about approvals, no history of reviews, no long lists of what is out of scope. Open with what the reader gets from the page.
4. **Skipped steps.** Your context is not the reader's. Say where a command runs (which directory, which machine, which cluster context), what it needs first, and what success looks like (the output, the status, the URL that now responds).

## Plain English rules

- Short sentences. One idea per sentence. Active voice: "The worker retries the job", not "The job is retried".
- Say what a thing is with "is" and "has". Not "serves as", "acts as", "boasts", "features".
- No "we", "our", "us", or "let's". In tutorials and how-to guides, address the reader as "you" ("Run X. You should see Y."). In explanation, reference, and ADRs, describe the system in the third person ("The router sends…").
- No metaphors, no rhetorical questions, no figurative language.
- No em dashes. Use a comma, colon, parentheses, or a new sentence.
- Straight quotes and apostrophes, not curly ones.
- Headings say what the section contains, in sentence case: "How requests are routed", not "Where The Magic Happens".
- No mention of AI, models, reviewers, or review tooling (Claude, Codex, GPT, "the review found") in repo docs or PR bodies, unless the system being documented is itself about models.
- Every concept gets a worked example with concrete, real-looking values: a real request, a real record, a real config snippet, and what comes out the other end.

## Diagrams

The most common problem with diagrams is that they are missing. The second is jargon in their labels.

- Use mermaid. Nothing else.
- Put a diagram first, before the prose, whenever the text describes components that talk to each other, a request or data flow, or a lifecycle with states. Do this unprompted.
- Pick the type by what you are showing:
  - which parts exist and what talks to what: `flowchart`
  - what happens in order across parts: `sequenceDiagram`
  - the states something moves through: `stateDiagram-v2`
  - how records relate: `erDiagram`
- Labels use plain words. If a node must carry a project name, the prose right after the diagram defines it. No ticket IDs, no file paths, no abbreviations the page has not defined.
- One diagram shows one idea. A second idea gets a second diagram.
- After the diagram, walk through it in numbered steps that match the arrows.

## Claims match the code

- Reference implementations by repo-relative path and symbol name (`services/router/rules.py` `load_rules`), not line numbers. Line numbers go stale.
- Read code from the remote default branch (`git show origin/<default>:<path>`), not a possibly stale worktree, unless the doc is about unmerged work on the current branch.
- Anything designed but not built is labelled so in the sentence ("Not built yet: …"). Never describe a planned behaviour in the present tense.

## Before hand-off

1. Run the prose check on what you wrote:
   - files: `~/.claude/skills/documentation/scripts/check-prose.py docs/how-to/rotate-keys.md`
   - only the lines a branch adds: `~/.claude/skills/documentation/scripts/check-prose.py --diff origin/main`
   - a PR body: `gh pr view 123 --json body -q .body | ~/.claude/skills/documentation/scripts/check-prose.py --pr -`
2. Fix every hit, or confirm it is a false positive (a word inside a product name, a quoted error message).
3. Reread the draft once against `references/mannered-prose.md` for what the script cannot see.
4. Reread it once more as the default reader: is every project term defined on first use, is every step's location and success state stated?

## Delegating docs work to a sub-agent

- Use `model: "sonnet"` by default. If its output fails the prose check or the reread, redo the work with `model: "opus"`. If the user names a model in the request, use that model.
- The brief tells the agent to read `~/.claude/skills/documentation/SKILL.md` and the matching reference file first, names the reader, and says to run the prose check before reporting back.
- Restate the user's working rules in the brief (for example: targeted edits rather than whole-file rewrites, minimal code comments, small sequential commits, no AI attribution lines in commits or PRs).
- Run the prose check on the agent's diff yourself before showing the user the result.
