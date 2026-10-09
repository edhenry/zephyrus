# Mannered prose

Mannered prose is writing that calls attention to its own style instead of carrying information. Readers also recognise most of these patterns as signs of machine-written text, and stop trusting the page. Each entry has an example to cut and a plain replacement.

`scripts/check-prose.py` catches the patterns marked **(checked)**. The rest need a reread.

## Sentence shapes

**Contrast setups (checked, partly).** A sentence that knocks down a claim nobody made.
- Cut: "This isn't about speed, it's about safety." / "Not just a cache, but a consistency layer." / "No YAML, no restarts, just a flag."
- Write: "The change makes deploys safer. It does not make them faster."

**Punchy fragments (checked, partly).** Short dramatic pieces or a question answered by the writer.
- Cut: "The fix? Simple." / "One flag. Two services. Zero downtime." / "Here's the thing:"
- Write: "Setting `ROUTER_STRICT=true` fixes it, without a restart."

**Signposting openers (checked).** Sentences that start by telling the reader how to feel about the sentence: Crucially, Notably, Importantly, Ultimately, Essentially, Additionally, In short, At its core, Put simply.
- Delete the opener. If the sentence needs emphasis, move it earlier on the page.

**Rule-of-three lists.** Three adjectives or clauses chosen for rhythm, not because there are exactly three facts.
- Cut: "fast, reliable, and simple"
- Write the facts that are true and measurable: "Median latency is 40 ms."

**"-ing" tails.** A clause tacked onto the end of a sentence that claims significance without adding information.
- Cut: "The worker retries failed jobs, ensuring reliability." / "…, highlighting the importance of idempotency."
- Write: "The worker retries a failed job up to three times."

**False ranges.** "From X to Y" where X and Y are not two ends of a scale.
- Cut: "Everything from logging to billing."
- Write the list: "Logging, metrics, and billing."

**Recaps.** A closing paragraph that repeats what the section just said, or an opener that announces what it will say ("In this guide, you will learn…").
- Delete both. The headings already say what is on the page.

## Word choices

**Filler intensifiers (checked).** genuinely, actually, really, truly, deeply, incredibly, extremely, basically, essentially, obviously, clearly, simply, just, honest, honestly.
- Delete them. The sentence is the same without them.

**Inflated significance (checked, partly).** plays a crucial/pivotal/key/vital role, is a testament to, underscores, marks a shift, sets the stage for, evolving landscape, cornerstone, indelible.
- Say what the thing does.

**Marketing verbs in place of "is" and "has" (checked, partly).** serves as, stands as, acts as, boasts, features, offers, showcases.
- "The gateway is the only entry point", not "The gateway serves as the sole entry point".

**AI vocabulary (checked).** delve, tapestry, intricate, interplay, meticulous, pivotal, crucial, vibrant, robust, seamless, leverage, foster, garner, bolster, showcase, streamline, holistic, synergy, paradigm, empower, unlock, game-changer, cutting-edge, elegant, powerful, first-class, journey.

**Personal banned list (checked; edit to taste).** golden path, north star, landmine, story (meaning "the explanation" or "the situation"), "surface" as a noun ("the API surface"), "honest" for emphasis.

**Vague authorities.** "Experts recommend", "It is widely considered", "Industry best practice is".
- Name the source and link it, or state the reason directly.

**Hedge-and-reassure (checked).** Don't worry, It's worth noting, Worth noting, As you might expect, Of course, Needless to say, Rest assured.
- Delete. If something is surprising, say what and why.

## Formatting

**Bold lead-in bullets.** Every bullet starting with a **bolded phrase:** followed by its explanation. Use plain bullets, or a table if each item has the same fields.

**Clever headings (checked: Title Case).** Puns, teasers, or Title Case. Headings say what the section contains, in sentence case.

**Overused bold.** Bold marks the one thing a reader scanning the page must not miss. A page with bold in every paragraph has no emphasis left.

**Em dashes (checked).** Not used. Comma, colon, parentheses, or a new sentence.

**Curly quotes (checked).** Use straight quotes.

**Emoji as formatting.** None, including check marks and warning signs in headings or tables. Write "Yes", "No", "Warning:".

**Tables that should be sentences.** A table with one row, or with one meaningful column, is a sentence.

**Formulaic endings.** "Challenges and future outlook", "Despite these challenges…", "Looking ahead". End the page when the content ends. Open work goes in a "Not built yet" list with specifics.
