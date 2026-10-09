# ADRs and design docs

ADRs use the MADR template. The additions here are a plain-English context section written for someone who does not know the names involved, a mermaid diagram, and a worked example. ADRs live in `docs/adr/`, numbered `NNNN-short-title.md`, unless the repo already keeps them elsewhere.

~~~markdown
---
status: proposed | accepted | rejected | deprecated | superseded by ADR-NNNN
date: YYYY-MM-DD
decision-makers: <names>
---

# <The decision, as a short sentence: "Store user sessions in Redis">

## Context and problem statement

What the system does today, in plain English, with every project term defined on first use.
Then the problem: what is not working, or what is about to be needed, and why it has to be
decided now.

```mermaid
<the part of the system the decision affects>
```

## Worked example

One concrete case that shows the problem: a real-looking request, record, or workload, and
what happens to it today. Each option below refers back to this example.

## Decision drivers

- The constraints and goals that decide between the options, specific and checkable
  ("must run without a managed cloud service", "p95 read under 10 ms at 50k active sessions").

## Considered options

- Option A
- Option B
- Option C

## Decision outcome

Chosen option: "Option B", because <the drivers it satisfies that the others do not>.

### Consequences

- Good, because …
- Bad, because …

### Confirmation

How anyone can check the decision is being followed: the code path, test, lint rule, or
config that enforces it, by path and symbol.

## Pros and cons of the options

### Option A

What it is in one or two sentences, and what happens to the worked example under it.

- Good, because …
- Bad, because …

### Option B

…

## More information

Links to related ADRs, explanation pages, and external sources. Ticket IDs go here and
nowhere else in the ADR.
~~~

## Rules specific to ADRs

- The title is the decision, not the topic. "Store user sessions in Redis", not "Session storage".
- The context section is the hardest part and the one most often sent back. Write it for someone who has never heard the system's names. If a reader needs three other docs to follow it, it is not done.
- Each option is described fairly enough that someone who preferred it would agree with the description.
- The "Bad, because" list for the chosen option is never empty.
- No history of how the decision was reached (meetings, review rounds, who argued what).
- Outside the `decision-makers` field, never name a person in the body, the PR body, or the open-questions table ("Alex decided"). State the decision as the ADR's own.
- Design docs that are not decisions (a proposal for how to build something) use the explanation-page rules in `diataxis.md`, plus a "Not built yet" section, and link the ADRs they depend on.
