# Repository docs (diataxis)

Diataxis sorts documentation into four kinds by what the reader is trying to do. Each page is exactly one kind. When a page starts doing two jobs, split it and link the halves.

| Kind | Reader is… | Page answers | Voice |
|---|---|---|---|
| Tutorial | learning, start to finish, with nothing set up | "Walk me through it once so I see it work" | "you", imperative steps |
| How-to guide | doing a specific task they already understand | "How do I rotate the signing key?" | "you", imperative steps |
| Explanation | building a mental model | "How does this work, and why is it built this way?" | third person |
| Reference | looking up a fact | "What are the fields, flags, endpoints, limits?" | third person, terse |

## Layout

Follow the repo's existing layout when it has one. When `docs/` is missing or unstructured, use:

```
docs/
  README.md          entry point
  tutorials/
  how-to/
  explanation/
  reference/
    glossary.md
  adr/
```

`docs/README.md` has, in order: one sentence on what the system is, one top-level mermaid diagram of the whole system, a reading order for a new engineer (which three or four pages to read first, and why), then a list of every page grouped by kind.

## Glossary

`docs/reference/glossary.md` has one entry per project term: the term, a one-sentence definition, and a link to the explanation page that covers it. Pages still define each term on first use. The glossary keeps pages using the same word for the same thing. When a page introduces a new term, add it to the glossary in the same change.

## Tutorials

- Start with what the reader will have at the end ("By the end you will have a local router answering requests from a test client").
- List what they need before step 1: tools with versions, access, which repo is checked out where.
- Number every step. Each step is one action, the exact command or click, and what the reader should see afterwards.
- Use one worked example from start to finish. Do not branch into options; link to how-to guides for those.
- End with what to read next.

## How-to guides

- Title is the task: "Rotate the signing key", not "Key rotation".
- One paragraph on when you would need this, then prerequisites, then numbered steps.
- State where each command runs and what success looks like.
- Include the failure cases a reader is likely to hit, as "If you see X, it means Y. Do Z."

## Explanation

- Open with a diagram of the part of the system the page covers, then a numbered walk through it.
- Explain why it is built this way, with the trade-off it accepts. Link to the ADR for the full decision.
- Include a worked example that follows one concrete input through the system, including what happens when it fails.
- A table of what is live versus designed, dated, when the system is partly built.

## Reference

- Generated from the code when the code can produce it (OpenAPI, CLI `--help`, schema files). Otherwise mirror the code's structure.
- Every field, flag, or endpoint: name, type, default, allowed values, one-line meaning, and the path and symbol that implements it.
- No narrative. Link to explanation pages for the why.

## Keeping docs current

When feature work in a repo with a `docs/` folder changes behaviour, the same PR updates the matching page. Put the docs in their own commit. New behaviour usually means a how-to change and sometimes an explanation change. New config, flags, or endpoints mean a reference change. New terms mean a glossary change.

## Normative documents

Some repo docs are contracts that other code or teams rely on word for word (API contracts, schema specs). Do not rewrite their normative text for style. Add a short reader's guide at the top that explains in plain English what the contract covers, who relies on it, and how to read it.

Plans, review notes, and other working documents that must be kept go in `docs/archive/`, which is the only place process history appears.
