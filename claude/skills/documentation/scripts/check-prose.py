#!/usr/bin/env python3
"""Flag banned words, mannered-prose patterns, and AI tells in Markdown prose.

Usage:
  check-prose.py FILE...              check whole files
  check-prose.py --diff BASE          check only lines added since the merge base with BASE
  check-prose.py --pr -               check stdin as a PR body (ticket IDs allowed)

Set PROSE_TICKET_PREFIX (a regex, e.g. "ENG|OPS") to flag only your tracker's ticket IDs.

Code blocks and inline code are skipped; mermaid blocks are checked. Exits 1 when anything is flagged.
"""
import argparse
import os
import re
import subprocess
import sys

I = re.IGNORECASE

WORDS = (
    "leverage leverages leveraged leveraging robust robustly seamless seamlessly powerful elegant elegantly "
    "first-class delve delves delving tapestry testament pivotal crucial crucially vibrant meticulous "
    "meticulously intricate intricacies interplay showcase showcases showcasing underscore underscores "
    "underscoring bolster bolstered garner garners foster fosters fostering streamline streamlined holistic "
    "synergy paradigm empower empowers unlock unlocks game-changer cutting-edge journey landscape cornerstone "
    "indelible boasts"
).split()
FILLERS = (
    "simply just genuinely actually really truly deeply incredibly extremely basically essentially obviously "
    "clearly honest honestly"
).split()

RULES = [
    ("em-dash", re.compile(r"—|\s--\s|\s–\s")),
    ("curly-quote", re.compile(r"[“”‘’]")),
    ("emoji", re.compile(r"[\U0001F300-\U0001FAFF☀-➿⭐⭕]")),
    ("banned-word", re.compile(r"\b(" + "|".join(map(re.escape, WORDS)) + r")\b", I)),
    ("filler", re.compile(r"\b(" + "|".join(FILLERS) + r")\b", I)),
    ("banned-phrase", re.compile(r"\b(golden paths?|north stars?|landmines?|the story|surface area)\b", I)),
    ("maybe-noun-surface", re.compile(r"\bsurfaces?\b", I)),
    ("inflated", re.compile(
        r"\b(plays? an? (crucial|key|pivotal|vital|central|important) role|is a testament|testament to|"
        r"sets? the stage|marks? a shift|evolving landscape|deep dive|in the heart of)\b", I)),
    ("ing-tail", re.compile(
        r",\s+(ensuring|highlighting|underscoring|emphasizing|emphasising|reflecting|showcasing|cementing|"
        r"solidifying|paving the way|setting the stage|making it (easy|easier|possible))\b", I)),
    ("marketing-verb", re.compile(r"\b(serves as|serve as|stands as|acts as)\b", I)),
    ("hedge", re.compile(
        r"\b(don't worry|do not worry|(it's |it is )?worth noting|as you might expect|of course|"
        r"needless to say|rest assured)\b", I)),
    ("recap-opener", re.compile(r"\b(in this (guide|doc|document|page|section|tutorial),? (we|you) will|you will learn)\b", I)),
    ("signpost", re.compile(
        r"(?:^|[.!?:]\s+|^\s*[-*]\s+)(Crucially|Notably|Importantly|Ultimately|Essentially|Additionally|"
        r"In short|At its core|Put simply|Simply put|In summary|To summarize)\b")),
    ("contrast", re.compile(
        r"\bnot (just|only|merely)\b|\b(isn't|is not|it's not|it is not|aren't|are not)\b[^.;]{0,60}?,\s*(it's|it is|they're|they are)\b|"
        r"\bno [^,.]{1,30}, no [^,.]{1,30}, just\b", I)),
    ("punchy", re.compile(r"here's the (thing|catch|kicker|deal)|^\s*(The|So) \w+\?\s|\?\s+(Simple|Easy|Nothing|None)\.", I)),
    ("first-person-plural", re.compile(r"\b(we|we're|we've|we'll|we'd|our|ours|ourselves|let's)\b", I)),
    ("first-person-plural", re.compile(r"\bus\b")),
    ("ai-mention", re.compile(
        r"\b(Claude(?!\.md)|Codex|ChatGPT|GPT-?\d[\w.-]*|Opus|Sonnet|Haiku|Fable|Gemini|review rounds?|reviewer model|"
        r"Co-Authored-By|Generated with)\b", I)),
]
NOT_TICKETS = "UTF|SHA|ISO|CVE|RFC|HTTP|TLS|SSL|AES|RSA|MD|PEP|ADR|SPEC|IPV|X|ES|P|E|A|B|C|K8S"
TICKET_PREFIX = os.environ.get("PROSE_TICKET_PREFIX", r"(?!(?:" + NOT_TICKETS + r")-)[A-Z][A-Z0-9]{1,9}")
TICKET_RULE = ("ticket-id", re.compile(
    r"\b(?:" + TICKET_PREFIX + r")-\d+\b|\b(PR|pull request)\s*#\d+|(?<![\w#/])#\d{2,5}\b"))

SMALL = set("a an the of to and or in on for with at by from as is are vs via into over per".split())


def strip_inline(line):
    line = re.sub(r"`[^`]*`", lambda m: " " * len(m.group()), line)
    line = re.sub(r"\]\([^)]*\)", lambda m: "]" + " " * (len(m.group()) - 1), line)
    return re.sub(r"https?://\S+", lambda m: " " * len(m.group()), line)


def title_case(heading):
    words = [w for w in re.findall(r"[A-Za-z][\w'-]*", heading)][1:]
    words = [w for w in words if w.lower() not in SMALL and not w.isupper()]
    caps = [w for w in words if w[0].isupper()]
    return len(words) >= 2 and len(caps) >= 2 and len(caps) / len(words) >= 0.75


def check_text(text, allow_tickets):
    rules = RULES if allow_tickets else RULES + [TICKET_RULE]
    hits, fence, bold_run = [], None, []
    for n, raw in enumerate(text.splitlines(), 1):
        m = re.match(r"^\s*(`{3,}|~{3,})\s*(\w*)", raw)
        if m:
            if fence is None:
                fence = (m.group(1)[0], m.group(2).lower())
            elif m.group(1)[0] == fence[0]:
                fence = None
            continue
        if fence and fence[1] != "mermaid":
            continue
        line = strip_inline(raw)
        if fence:
            line = re.sub(r"#[0-9a-fA-F]{3,8}\b", lambda m: " " * len(m.group()), line)
        for name, rx in rules:
            for hit in rx.finditer(line):
                hits.append((n, name, hit.group().strip(), raw.strip()))
        h = re.match(r"^#{1,6}\s+(.*)", line)
        if h and title_case(h.group(1)):
            hits.append((n, "title-case-heading", h.group(1).strip(), raw.strip()))
        if re.match(r"^\s*([-*]|\d+\.)\s+\*\*[^*]+\*\*", raw):
            bold_run.append((n, raw.strip()))
        elif raw.strip():
            if len(bold_run) >= 3:
                hits += [(bn, "bold-lead-in-list", "", br) for bn, br in bold_run]
            bold_run = []
    if len(bold_run) >= 3:
        hits += [(bn, "bold-lead-in-list", "", br) for bn, br in bold_run]
    return hits


def added_lines(base):
    out = subprocess.run(
        ["git", "diff", "-U0", "--merge-base", base, "--", "*.md", "*.mdx"],
        check=True, capture_output=True, text=True,
    ).stdout
    added, path = {}, None
    for line in out.splitlines():
        if line.startswith("+++ "):
            path = None if line[4:] == "/dev/null" else line[6:]
        elif line.startswith("@@") and path:
            m = re.search(r"\+(\d+)(?:,(\d+))?", line)
            start, count = int(m.group(1)), int(m.group(2) or 1)
            added.setdefault(path, set()).update(range(start, start + count))
    return added


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*")
    ap.add_argument("--diff", metavar="BASE")
    ap.add_argument("--pr", action="store_true", help="allow ticket IDs and PR numbers")
    args = ap.parse_args()

    targets = []
    if args.diff:
        root = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()
        for path, lines in added_lines(args.diff).items():
            targets.append((path, open(f"{root}/{path}", encoding="utf-8").read(), lines))
    for f in args.files:
        targets.append(("<stdin>" if f == "-" else f, sys.stdin.read() if f == "-" else open(f, encoding="utf-8").read(), None))
    if not targets:
        ap.error("give files, '-' for stdin, or --diff BASE")

    total = 0
    for path, text, only in targets:
        for n, name, match, line in check_text(text, args.pr):
            if only is not None and n not in only:
                continue
            total += 1
            shown = f' "{match}"' if match else ""
            print(f"{path}:{n}: {name}{shown}  | {line[:140]}")
    if total:
        print(f"\n{total} hit(s). Fix each, or confirm it is a false positive.", file=sys.stderr)
    sys.exit(1 if total else 0)


if __name__ == "__main__":
    main()
