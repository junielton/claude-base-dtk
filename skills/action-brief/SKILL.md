---
name: action-brief
description: >-
  Turn what a session or a delivery produced (reports, findings, open
  questions, follow-ups) into a verified brief of WHAT IS STILL OPEN AND WHO
  HAS TO ACT, for either audience: a self-contained text for the team or the
  client (usable as is in Slack, email, a doc or a ticket, with no greeting or
  opening addressed to anyone), or the same action points handed back to the
  user at the end of any session. Every claim is checked against its primary
  source by an independent claim-verifier agent, every page, doc or PR
  mentioned gets a working link from a link-finder agent, and the text is
  simple and explanatory for a reader with no prior context. Use it at the end
  of any piece of work that leaves pending items, and whenever the user asks,
  in any language, for "a message for the team", "an executive update", "the
  action points", "what's still pending", "the questions for the client",
  "what do I need to do now", "write the team report", "turn this report into
  a message", even when they only say "write the message" after a long
  session. Do NOT use it for a one-off reply to a single message (a
  reply-drafting or voice skill), for a PR description (create-pr), or for the rail of steps a run
  executed (report-back covers what was DONE; this skill covers what is still
  OPEN, and report-back can hand off to it).
---

# Action brief

The end of a piece of work leaves a list of things someone else has to do:
answer a question, send content, decide something, run a step. This skill turns
that list into a brief people can act on without having been in the work.
They act on it, forward it, or quote it to a client.

Two failures matter, and the skill exists to prevent both:

- **A wrong or vague item.** It is worse than no item. "The doc contradicts
  itself" when it doesn't costs the sender credibility. So does an item so short
  the reader has to ask "what do you mean?".
- **An item that isn't theirs.** Asking the client something we could fix
  ourselves is embarrassing, and so is raising something that breaks nothing
  for a real user. In a brief back to the user, it means handing them work that
  was ours to do.

So most of the work is *filtering and proving*, and only then *writing*.

## 0. Pick the audience and pin down the frame

There are two audiences. The pipeline is the same for both; only steps 2 and 5
differ.

| | **Outward** (team, client) | **Back to the user** |
|---|---|---|
| Asked as | "message for the team", "client update", "team report" | "action points", "what's pending", "what do I need to do", end of a session |
| Language | the language the readers work in (ask if unclear; English by default), in the user's own voice skill when there is one (tone only: no greeting, not addressed to anyone) | the language the user is speaking, summary first, short |
| Keeps | only items the reader alone can settle | the same, plus our own follow-ups, each with a recommendation |
| Delivered as | a file to copy and paste | a file plus a short answer in chat |

Then pin down, asking only what you cannot infer:
- **Who reads it** and what each person can decide (PM, client, designer, QA).
  Group the asks by who answers them.
- **When it goes out.** If it is sent after something lands (a merge, a
  deploy), drop everything that only describes pending work.
- **Where the sources are**: the session's transcript, the living report,
  action-point lists, registers, PRs, the source sheet.

## 1. Harvest candidate items

List every possible item from the sources: status facts, open questions,
missing content, contradictions, design gaps, follow-ups. One line each, with
hints for where it came from. The list is deliberately too long; the next steps
cut it.

## 2. Gate each item before spending effort on it

| Question | Outward | Back to the user |
|---|---|---|
| Could we fix it ourselves (our code, our data, a placeholder we left)? | Cut. Offer a task card instead. | Keep, under "Ours", with a recommendation (card it, fix it now, or drop it). |
| Does it break nothing a real user sees? (a stale design frame while the live page is right, an optional slot, a naming preference, a nicety the docs mention) | Cut. If the reader wants it, they will send it. | Mention in one line only if the user may care; otherwise cut. |
| Is it about the local environment (tokens, tooling, a machine)? | Cut. It is never the reader's business. | Keep only if the user must act on it. |
| Already resolved, or about work that will have landed by send time? | Cut. | Cut. |
| An ask nobody needed (please QA X, does someone want to send Y)? | Cut unless the user asked for it. | Cut. |

What survives an outward brief is a claim that something is wrong or missing
and that only the reader can settle.

## 3. Prove every surviving claim: the claim-verifier agent

Spawn **`dtk:claim-verifier`** agents (`subagent_type: "dtk:claim-verifier"`).
Give each a batch of 3 to 6 claims with source hints. Run the batches in
parallel, never more than half the machine's cores at once. If the agent type
is not listed, spawn `general-purpose` with the body of
`${CLAUDE_PLUGIN_ROOT}/agents/claim-verifier.md` as its prompt.

Brief each one with the claim exactly as it would read, plus where to look (doc
ids, page URLs, record paths, PR numbers). Don't say what you expect to find,
so the verdict stays independent of yours. Status facts count as claims too
("86 pages live", "all PRs merged").

Act on the verdicts:
- `confirmed`: keep it. Build the item from the verifier's quotes and plain
  explanation.
- `wrong`: drop it, or correct it if the true version is still an item. If the
  wrong version was already shown to the user, say plainly that it was wrong
  and why.
- `weak`: drop it by default. Keep it only when the uncertainty itself is the
  question, and say so honestly.
- Who acts `us` / `nobody`: route it by the gate above.

## 4. Link everything: the link-finder agent

Once the item list is final, list every mention of a page, doc, PR, sheet or
design frame. Count each one: an item that names six pages has six mentions.
Spawn one **`dtk:link-finder`** agent (`subagent_type: "dtk:link-finder"`; or
`general-purpose` with `${CLAUDE_PLUGIN_ROOT}/agents/link-finder.md` as its
prompt) with that list, the environment base URLs, and where links are
recorded.

Use what it returns:
- Put every mention's link inline, on the words the reader clicks:
  "[Pricing](…)", not "Pricing (link)".
- When an item is about a doc's content, link **both** the page where it shows
  and the doc it comes from.
- A mention with no verifiable link gets reworded or pointed at the nearest
  working page. Never ship a link that wasn't checked.

## 5. Write it

**For both audiences:**
- **Assume zero context.** Every item says, in plain words, four things: what
  is wrong, where it is (with a link), what the source actually says (a short
  quote), and what we need. No internal vocabulary without a gloss: "record",
  "slot", "frame", "DTO" and "register" mean nothing to a PM.
- **Lead with status, then the asks.** Open with one short "where we are" block,
  then the asks grouped by who answers them.
- **Each ask ends in a question answerable in one line**, such as "Which cards
  should it show?" or "Keep it, or what should it say?".
- **Show, don't characterize.** Don't write "copy that looks pasted by mistake".
  Write "the Pro plan page lists the Starter plan's features ('Up to 3 users',
  'Email support only'). It's the Starter copy."

**Outward:** the text is not a message to someone. It has no greeting, no
salutation, no name or team addressed ("Hey team", "Hi Ana", "Quick update"),
and no sign-off. Its first line is the status block. That is what lets the user
paste it anywhere: a Slack thread, an email body, a doc, a ticket. If they want
it framed as a message, they add the opening themselves or ask for it.
Whenever possible, write it in the voice of whoever runs the skill, so it
doesn't come out robotic: look for a voice skill in the current environment (one the user
installed, or the project's own) and load it. Take only its tone and word
choice. Leave out its message shape (greeting, human line, close), which is
exactly what this text must not have. With no voice skill available, write
plain, natural sentences. Then:
- write rendered Markdown, ready to paste: bold group headings, numbered asks,
  nested bullets for detail;
- no `@mentions`, because the user tags people themselves, and no Slack
  `<url|text>` syntax;
- no em or en dashes;
- no internal references: no task card ids, local paths or session ids, and
  not the words "orchestrator" or "operator";
- no closing pleasantries unless the user asks, so the asks are the end.

**Back to the user**, in their language:
- one opening line with the state;
- **Needs you**, numbered, each item with its links and the action;
- **Ours**, each item with a recommendation;
- glossed terms; no report of what was done (that belongs to `report-back`).

A good item:

> **Starter copy on the Pro plan page.** The [Pro plan page](…) lists the
> Starter plan's features ("Up to 3 users", "Email support only"), and so does
> the Pro section of the [pricing doc](…). It is the same text as the
> [Starter section](…). So the Pro page sells a different plan.

An item that should never have reached the reader:

> [Home] says "1,200+ customers" in one spot and "1,500+" in another.

In the doc the labels differ: one is "active customers", the other "customers
served since launch". Nobody checked the labels before calling it a
contradiction.

## 6. Deliver

- Write the brief to a file: the project's ignored output folder when it has
  one (for example `.harnu/out/<slug>.md` in a Harnu repo), otherwise the
  scratchpad. Open it in a viewer pane when the environment has one, and point at it in one line rather than pasting
  it. The exception is a brief back to the user of three items or fewer:
  answer that in chat.
- Before opening it, check mechanically:
  - outward: no `—` or `–` and no `@`; the first line is the status block,
    not a greeting or a name ("Hey", "Hi", "Hello", "Team,");
  - every URL in the file is in the link-finder's 200 table.
- In chat, say in two or three lines what the gate cut and why, so the user can
  pull an item back in.

## 7. The review loop

The user reads it item by item, and their replies are short, in any language.
Handle them like this:

- **"I don't get it" / "explain" / a pasted item with a question.** Answer in
  chat with the evidence: the quote, the links, what is actually true. Then
  recommend keeping it with a rewrite, or removing it. If the explanation shows
  the item was wrong, say so in one sentence and don't defend it.
- **"remove" / "drop it".** Remove the item and renumber. Fix any intro line
  that now over-promises (for example "for the client or design" once the
  design section is gone). Reopen the file.
- **"add the link" / "explain it better".** Rerun steps 3 and 4 for that item
  and rewrite it to the zero-context standard, with page and doc links.
- **"apply your recommendations".** Apply every recommendation from that round,
  then say what changed.
- **After each edit, check that the structure still holds.** If a section is
  down to one weak item, recommend removing the whole section.
- **Leave the user's own edits alone** unless they ask. If something they
  likely removed is gone, mention it once ("the batch list is no longer in the
  file; if that wasn't you, I'll restore it").

## 8. Close

When the user says it's ready:
- any `us` items found along the way become task cards, if they agree;
- anything durable they taught about tone or filtering goes into this skill's
  `LESSONS.md` (via `skill-learn`, when it is available).
