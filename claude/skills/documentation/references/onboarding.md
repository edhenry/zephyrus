# Onboarding and explainer artifacts

The reader is an engineer who has never seen these systems and needs to understand quickly what does what, where, why, and how. These are often published as a single page (an HTML artifact) or as an onboarding doc in a repo.

## Structure

1. **What this is, in two sentences.** What the system does for its users, and what the reader will understand by the end.
2. **The whole picture.** One block diagram (`flowchart`) of every component on the page and what talks to what, with plain-word labels. Follow it with one sentence per component: what it is and what it owns.
3. **One thing, end to end.** Pick the most important flow (a request, a run, an investigation) and follow one concrete example through every component with a `sequenceDiagram`, then numbered steps that match the arrows. Show the data at each hop: the actual fields of the request, the row written, the event emitted.
4. **What can go wrong.** The same flow's main failure paths: what fails, what the system does about it, and what the operator sees.
5. **Where it lives.** A table of component, repo, main entry point (path and symbol), and how it is deployed.
6. **Words you will see.** A glossary of every project term on the page, each defined in one sentence.
7. **Live versus designed.** A dated table of which parts run today and which are designed but not built.
8. **Where to go next.** Links to the repo docs, ADRs, and dashboards, with one line on why to read each.

## Rules specific to onboarding pages

- Every claim is checked against code on the remote default branch of each repo involved, not a local worktree.
- When the page spans several repos, read each sibling repo with `git show origin/<default>:<path>`.
- When a word means different things in different parts of the system ("operator" as a person in one place and a service role in another), define each meaning where it is used and never let one stand for the other.
- Prefer several small diagrams, one per idea, over one diagram of everything beyond step 2.
