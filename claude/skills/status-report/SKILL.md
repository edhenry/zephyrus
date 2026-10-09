---
name: status-report
description: How to answer status, progress, and decision questions in chat. Use it whenever the user asks "what's the status", "where are we at", "how are we doing relative to the overall effort", "what do you need from me", "what decisions do you need", "what can I merge and in what order", "walk me through the options", or says they are lost or have been away. Also use it when presenting any decision for the user to make, and when the user answers decisions by number or letter.
user_invocable: true
---

# Status and decision replies

The user reads these to decide what to do next. They have usually been doing other work since the last reply, merging PRs or running other sessions. Write so they can act after one read, without scrolling back.

The plain-English rules in `~/.claude/CLAUDE.md` apply, and `~/.claude/skills/documentation/references/mannered-prose.md` lists the patterns to avoid.

## First, re-check the real state

Before writing a status reply, look again. Do not answer from memory of earlier in the session.

- PRs in play: `gh pr view <n> --repo <owner/repo> --json state,mergeable,statusCheckRollup,baseRefName` for each one. Note which merged, which conflict, which have failing checks, and which stacked PRs now point at a merged base.
- Default branches: `git fetch` and read `origin/<default>` for each repo involved. Never trust a local worktree's view of what has merged.
- Background agents and workflows from this session: which finished, which are running, which failed.

Open the reply with what changed since the last update when anything did ("You merged api #34 and #35. web #36 now has a conflict.").

## Layout of a status reply

Use these four sections, in this order, with these headings. The whole reply fits on one screen, about 25 lines, not counting decision cards. The user asks when they want more detail on an item.

1. **Where things stand.** Two or three sentences: what the effort is for, how far along it is, and what remains between here and done. Measure against the whole effort, not the last task. "The importer handles two of the five source formats end to end. CSV and XML remain, plus the retry queue."
2. **Needs you.** Everything the user has to do, before anything else in the reply.
   - Merges, in order, with the reason for the order when there is one: "api #17, then web #32 (it calls the new endpoint)."
   - Decisions, by number (cards below).
   - Anything else only the user can do: a login, a secret, a ruleset change, a question for another person.
   - When nothing needs the user, say "Nothing needs you right now." in this section. Do not leave it out.
3. **Done since last update.** One line each, written as the effect: "Failed webhook deliveries now retry with backoff (ENG-1234)."
4. **Running now and next.** What is in progress and what starts after it, one line each.

## Identifiers

- PR numbers appear with their repo, and only where the user acts on them: merge lists and review requests.
- Ticket IDs go in parentheses after a plain description, so they can be found in the tracker.
- Leave out commit SHAs and test counts. Say "tests pass", or name what fails.
- No internal labels: finding codes (F3), invariant codes (I7), placeholder PR names (PR-A), lane, round, gate, slice, fold, workstream numbers. Say what the thing is.
- No review tooling: not "Codex approved", not "the reviewer found". Say what was found and whether it is fixed.

## Decisions

### Numbering

Number decisions across the whole session. Decision 13 stays decision 13 until the user answers it. Every status reply lists all open decisions. A decision appears as a full card the first time, and in short form after that, so the user can still answer without scrolling back:

```
Still open:
13. Retry failed imports automatically?  A retry 3 times, then park (recommended)  B never retry
```

### The decision card

```
Decision 4: Should an import with unknown columns still be accepted?

Today: unknown columns are dropped silently, so a renamed column in a customer's
export loses that data without anyone noticing.

A. Accept, and record a warning on the import. Nothing breaks, and the warning
   shows which columns were dropped.
B. Reject the whole file. Nothing is lost, but every renamed column stops an import
   until someone updates the mapping.

Recommend A. Downside: someone still has to read the warnings.
B blocks imports for the two customers who rename columns monthly.
Blocks: nothing. Safe to merge api #32 first.
```

- The title is the question, in plain words.
- "Today" explains the situation for someone who has not read the code. Define any project term here.
- Each option is lettered and says what it leads to, not just what it is.
- The recommendation names its main downside, even when the choice is clear.
- "Blocks" says what waits on the decision, or "nothing".

### When the user answers

The user may answer in shorthand ("B, your recommendation for 13, and 11 too"). Reply with one line per decision saying what will now happen, then do it. Record each decision where it belongs: the ticket, the ADR, the PR body, or memory if it outlives the session. Ask again only if an answer could mean two different things.

## Candor

- When the user's idea or choice looks weaker than an alternative, say so in the first sentence, with the reason and the alternative.
- Every recommendation states its main downside.
- For claims that matter, say how you know: checked (read in code on the default branch, seen live), inferred (follows from something checked), or a guess.
- No praise or agreement openers: not "Great question", "You're right", "Spot on", "Good call". Start with the answer.

## Answer only what was asked

When the user asks a narrow question ("What does that error code mean?", "Is kubectl not enough?"), answer that question directly in a few sentences. Do not wrap it in a full status reply.

## Catch-up after time away

When the user says they have been away, are lost, or are new to the effort, add these before "Where things stand":

1. **The goal.** What the effort is for and what "done" looks like, in two sentences.
2. **Map of the parts.** A small mermaid `flowchart` of the systems involved, with each node marked as working today, partly built, or not built.
3. **Changed while you were away.** What merged, what other sessions did, and which decisions were made, with dates.
4. **Words you'll see.** A short glossary of every project term the rest of the reply uses, one sentence each.

The one-screen limit does not apply to a catch-up reply.
