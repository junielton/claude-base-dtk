#!/usr/bin/env python3
"""Review outcomes: how posted reviews behave in production.

For the last N pull requests of a repo, measures per reviewer: comments per tag
(Q / CR / FFT / NIT / untagged), hedge and `suggestion` counts, review verdicts,
CR comments posted under a CHANGES_REQUESTED review, and, per tag, whether the
PR author's reply accepted or declined the comment.

Usage:
  python3 bin/skill-scripts/review/outcomes.py owner/repo --limit 50 \
      [--since YYYY-MM-DD] [--reviewer login] [--json]
  python3 bin/skill-scripts/review/outcomes.py --self-test

Needs `gh` already authenticated (`gh auth login`); no token is read or stored.
Method and baseline: docs/specs/2026-10-20-review-case-study.md section 8,
docs/review-outcomes.md.
"""

import argparse
import json
import re
import subprocess
import sys
from collections import Counter, defaultdict

TAGS = ("Q", "CR", "FFT", "NIT", "untagged")

# Banned phrases from docs/specs/2026-10-20-review-tone-and-evals.md, Changes 2.
# Keep in sync with bin/skill-scripts/review/tone-lint.sh once that lands (U1).
# Split in two groups so the numbers line up with the case study table:
# "hedges" and "marked optional".
HEDGE_PHRASES = ("might be worth", "maybe", "could be worth")
OPTIONAL_PHRASES = (
    "feel free to ignore",
    "totally optional",
    "take it or leave it",
    "fine to leave",
    "not a big deal",
    "just a thought",
)


def _phrase_re(phrases):
    return re.compile("|".join(re.escape(p) for p in phrases), re.IGNORECASE)


HEDGE_RE = _phrase_re(HEDGE_PHRASES)
OPTIONAL_RE = _phrase_re(OPTIONAL_PHRASES)
SUGGESTION_RE = re.compile(r"^\s*```suggestion\b", re.MULTILINE)
TAG_RE = re.compile(r"^\W*(Q|CR|FFT|NIT)\s*:", re.IGNORECASE)

# The author's reply text decides acceptance (case study section 8: `isOutdated`
# is a bad proxy, fixes often land in another file).
ACCEPTED_RE = re.compile(r"good catch|\bdone\b|\bfixed\b|\badded\b", re.IGNORECASE)
DECLINED_RE = re.compile(r"\bkeeping\b|\bintended\b|not for this pr|\balready\b", re.IGNORECASE)
SHA_RE = re.compile(r"\b[0-9a-f]{7}(?:[0-9a-f]{33})?\b", re.IGNORECASE)
# Not in the spec's marker list: a reply that opens by agreeing ("Good call, thanks!
# It now ...") but names none of the markers. Kept apart from `accepted` so the strict
# numbers stay the spec's; a leading `keep` ("Yeah, I'd rather keep it") is a decline.
AGREED_RE = re.compile(
    r"^\W*(good (call|point|eye|thinking)|nice catch|fair point|makes sense|agreed|"
    r"you'?re right|yeah|yep|true|right)\b",
    re.IGNORECASE,
)
KEEP_RE = re.compile(r"\bkeep\b", re.IGNORECASE)
# marked-wrong: the PR author's reply says the comment is wrong. Three explicit signals only:
# a leading `wrong:` tag, a thumbs-down, or "not an issue". Reactions are not fetched, so a thumbs-down reaction is not counted (only one typed in a reply).
MARKED_WRONG_RE = re.compile(r"^\W*wrong\s*:|\U0001f44e|not an issue", re.IGNORECASE | re.MULTILINE)

# The seven metrics of docs/review-outcomes.md "Definitions", in table order. These are the
# `--json` key names under `metrics`. `refuted_by_verifier` is always null: it is not measured yet.
METRIC_KEYS = (
    "posted",
    "refuted_by_verifier",
    "accepted",
    "resolved_by_merge",
    "marked_wrong",
    "hedges",
    "cr_as_cr",
)
NOT_MEASURED = ("refuted_by_verifier",)

PR_LIST_QUERY = """
query($owner: String!, $name: String!, $first: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequests(first: $first, after: $after, orderBy: {field: CREATED_AT, direction: DESC}) {
      pageInfo { hasNextPage endCursor }
      nodes { number createdAt }
    }
  }
}
"""

# One query per PR: reviews, review threads (comments, resolution, outdated), commits.
PR_QUERY = """
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      number state createdAt author { login }
      reviews(first: 100) { nodes { id state author { login } } }
      reviewThreads(first: 100) {
        nodes {
          isResolved isOutdated
          comments(first: 100) {
            nodes { author { login } body createdAt pullRequestReview { id state } }
          }
        }
      }
      commits(last: 100) { nodes { commit { oid } } }
    }
  }
}
"""


def gh_graphql(query, **variables):
    cmd = ["gh", "api", "graphql", "-f", f"query={query}"]
    for key, value in variables.items():
        flag = "-F" if isinstance(value, int) else "-f"
        cmd += [flag, f"{key}={value}"]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        sys.exit(f"gh api graphql failed: {proc.stderr.strip() or proc.stdout.strip()}")
    payload = json.loads(proc.stdout)
    if payload.get("errors"):
        sys.exit(f"GraphQL errors: {payload['errors']}")
    return payload["data"]


def list_prs(owner, name, limit, since):
    """Newest-first PR numbers, at most `limit`, created on/after `since` (YYYY-MM-DD)."""
    numbers, after = [], None
    while len(numbers) < limit:
        variables = {"owner": owner, "name": name, "first": min(100, limit - len(numbers))}
        if after:
            variables["after"] = after
        page = gh_graphql(PR_LIST_QUERY, **variables)["repository"]["pullRequests"]
        for node in page["nodes"]:
            if since and node["createdAt"][:10] < since:
                return numbers
            numbers.append(node["number"])
        if not page["pageInfo"]["hasNextPage"]:
            break
        after = page["pageInfo"]["endCursor"]
    return numbers


def fetch_pr(owner, name, number):
    return gh_graphql(PR_QUERY, owner=owner, name=name, number=number)["repository"]["pullRequest"]


def login(node):
    return (node.get("author") or {}).get("login") or "ghost"


def tag_of(body):
    match = TAG_RE.match(body or "")
    return match.group(1).upper() if match else "untagged"


def has_commit_sha(text, commit_oids):
    """A 7-hex token counts when it prefixes a commit of the PR, or contains a
    digit (so words like "defaced" are not read as a sha). The digit rule is
    needed because rebased and force-pushed branches no longer list the commit
    the author cited."""
    for token in SHA_RE.findall(text):
        token = token.lower()
        if any(oid.startswith(token) for oid in commit_oids) or any(ch.isdigit() for ch in token):
            return True
    return False


def classify_reply(replies, commit_oids):
    """Outcome of one thread from the PR author's replies: the last reply that
    carries a marker decides; declined markers win inside a single reply, and
    `agreed` (opener only) applies when no spec marker is present."""
    outcome = "replied"
    for text in replies:
        if DECLINED_RE.search(text):
            outcome = "declined"
        elif ACCEPTED_RE.search(text) or has_commit_sha(text, commit_oids):
            outcome = "accepted"
        elif AGREED_RE.match(text) and not KEEP_RE.search(text):
            outcome = "agreed"
    return outcome


def analyze(prs):
    comments = defaultdict(Counter)  # reviewer -> tag -> n
    hedges = Counter()
    optional = Counter()
    suggestions = Counter()
    verdicts = defaultdict(Counter)  # reviewer -> review state -> n
    cr_verdict = defaultdict(Counter)  # reviewer -> review state of each CR comment
    outcomes = defaultdict(lambda: defaultdict(Counter))  # reviewer -> tag -> outcome -> n
    tagged = defaultdict(lambda: defaultdict(Counter))  # reviewer -> tag -> metric -> n

    for pr in prs:
        author = login(pr)
        is_open = pr["state"] == "OPEN"
        oids = [n["commit"]["oid"] for n in pr["commits"]["nodes"]]

        for review in pr["reviews"]["nodes"]:
            reviewer = login(review)
            if reviewer != author and review["state"] != "PENDING":
                verdicts[reviewer][review["state"]] += 1

        for thread in pr["reviewThreads"]["nodes"]:
            nodes = thread["comments"]["nodes"]
            if not nodes:
                continue
            first = nodes[0]
            reviewer = login(first)
            if reviewer == author:
                continue  # the author starting a thread is not a review comment
            body = first["body"] or ""
            tag = tag_of(body)
            comments[reviewer][tag] += 1
            hedges[reviewer] += bool(HEDGE_RE.search(body))
            tagged[reviewer][tag]["posted"] += 1
            tagged[reviewer][tag]["hedges"] += bool(HEDGE_RE.search(body))
            optional[reviewer] += bool(OPTIONAL_RE.search(body))
            suggestions[reviewer] += bool(SUGGESTION_RE.search(body))
            if tag == "CR":
                review = first.get("pullRequestReview") or {}
                cr_verdict[reviewer][review.get("state", "NONE")] += 1
                tagged[reviewer][tag]["cr_as_cr"] += review.get("state") == "CHANGES_REQUESTED"

            replies = [c["body"] or "" for c in nodes[1:] if login(c) == author]
            if replies:
                outcome = classify_reply(replies, oids)
            elif is_open:
                outcome = "pending"  # open PR: not an ignored comment, not yet answered
            else:
                outcome = "no_reply"
            outcomes[reviewer][tag][outcome] += 1
            tagged[reviewer][tag]["marked_wrong"] += any(MARKED_WRONG_RE.search(t) for t in replies)
            tagged[reviewer][tag]["accepted"] += outcome == "accepted"
            tagged[reviewer][tag]["resolved_by_merge"] += outcome == "no_reply" and pr["state"] == "MERGED"

    return {
        "tagged": tagged,
        "comments": comments,
        "hedges": hedges,
        "optional": optional,
        "suggestions": suggestions,
        "verdicts": verdicts,
        "cr_verdict": cr_verdict,
        "outcomes": outcomes,
    }


def pct(part, whole):
    return f"{100 * part / whole:.0f}%" if whole else "-"


def render(result, reviewers):
    out = []
    for reviewer in reviewers:
        tags = result["comments"][reviewer]
        total = sum(tags.values())
        out.append(f"## {reviewer}  (n={total} inline comments)\n")

        out.append("| Tag | Comments |")
        out.append("|---|---|")
        for tag in TAGS:
            out.append(f"| {tag} | {tags[tag]} |")

        cr = result["cr_verdict"][reviewer]
        cr_total = sum(cr.values())
        verdicts = result["verdicts"][reviewer]
        verdict_text = ", ".join(f"{k} {v}" for k, v in sorted(verdicts.items())) or "none"
        out.append("")
        out.append("| Metric | Count |")
        out.append("|---|---|")
        out.append(f"| hedges (might be worth / maybe / could be worth) | {result['hedges'][reviewer]} |")
        out.append(f"| marked optional (feel free to ignore / fine to leave / totally optional / ...) | {result['optional'][reviewer]} |")
        out.append(f"| `suggestion` blocks | {result['suggestions'][reviewer]} |")
        out.append(f"| CR posted as CHANGES_REQUESTED | {cr['CHANGES_REQUESTED']}/{cr_total} |")
        out.append(f"| review verdicts | {verdict_text} |")

        out.append("\nAcceptance by the author's reply (open PRs without a reply are `pending`, not `no reply`):\n")
        out.append("| Tag | n | accepted | declined | agreed (opener only) | other reply | no reply | pending (open PR) | accepted % of n | accepted+agreed % of n |")
        out.append("|---|---|---|---|---|---|---|---|---|---|")
        for tag in TAGS:
            row = result["outcomes"][reviewer][tag]
            n = sum(row.values())
            if not n:
                continue
            out.append(
                f"| {tag} | {n} | {row['accepted']} | {row['declined']} | {row['agreed']} | {row['replied']} "
                f"| {row['no_reply']} | {row['pending']} | {pct(row['accepted'], n)} "
                f"| {pct(row['accepted'] + row['agreed'], n)} |"
            )
        out.append("")
    return "\n".join(out)


def metrics_of(counts):
    """The seven metrics of one reviewer-tag cell, in METRIC_KEYS order; unmeasured ones are None."""
    return {key: None if key in NOT_MEASURED else counts[key] for key in METRIC_KEYS}


def to_jsonable(result, reviewers):
    out = {}
    for reviewer in reviewers:
        by_tag = {tag: metrics_of(result["tagged"][reviewer][tag]) for tag in TAGS}
        total = Counter()
        for tag in TAGS:
            total.update(result["tagged"][reviewer][tag])
        out[reviewer] = {
            "comments": dict(result["comments"][reviewer]),
            "hedges": result["hedges"][reviewer],
            "optional": result["optional"][reviewer],
            "suggestions": result["suggestions"][reviewer],
            "cr_verdicts": dict(result["cr_verdict"][reviewer]),
            "verdicts": dict(result["verdicts"][reviewer]),
            "outcomes": {t: dict(c) for t, c in result["outcomes"][reviewer].items()},
            "metrics": {"total": metrics_of(total), "by_tag": by_tag, "not_measured": list(NOT_MEASURED)},
        }
    return out


def render_json(result, reviewers):
    return json.dumps(to_jsonable(result, reviewers), indent=2)


def self_test():
    assert tag_of("CR: this throws") == "CR"
    assert tag_of("**FFT:** x") == "FFT"
    assert tag_of("nit: x") == "NIT"
    assert tag_of("👍") == "untagged"
    assert tag_of("Q: why?") == "Q"
    assert HEDGE_RE.search("This Might Be Worth a look")
    assert OPTIONAL_RE.search("Feel free to ignore")
    assert not HEDGE_RE.search("I'd extract this")
    assert SUGGESTION_RE.search("Rename:\n```suggestion\nfoo\n```")
    oids = ["abc1234def5678"]
    assert classify_reply(["Good catch, thanks"], oids) == "accepted"
    assert classify_reply(["Fixed in abc1234"], oids) == "accepted"
    assert classify_reply(["Keeping this one"], oids) == "declined"
    assert classify_reply(["Good catch, but keeping it"], oids) == "declined"
    assert classify_reply(["Reworded (060299c)"], oids) == "accepted"  # rebased: not in oids
    assert classify_reply(["defaced"], oids) == "replied"  # 7 hex letters, not a commit
    assert classify_reply(["Good call, thanks! It now stubs it"], oids) == "agreed"
    assert classify_reply(["Yeah, I'd rather keep it"], oids) == "replied"
    assert classify_reply(["Hmm, let me think"], oids) == "replied"
    assert classify_reply(["Keeping this", "Done after all"], oids) == "accepted"

    def comment(who, body, review=None):
        return {"author": {"login": who}, "body": body, "createdAt": "", "pullRequestReview": review}

    def pr(state, threads, reviews=()):
        return {
            "state": state,
            "author": {"login": "dev"},
            "reviews": {"nodes": [{"id": i, "state": s, "author": {"login": "rev"}} for i, s in enumerate(reviews)]},
            "reviewThreads": {"nodes": [{"comments": {"nodes": t}} for t in threads]},
            "commits": {"nodes": []},
        }

    review = {"id": "r", "state": "COMMENT"}
    merged = pr(
        "MERGED",
        [
            [comment("rev", "CR: breaks. Maybe fix it, feel free to ignore", review), comment("dev", "Done")],
            [comment("rev", "FFT: x\n```suggestion\ny\n```", review)],
        ],
        reviews=("COMMENT", "APPROVED"),
    )
    open_pr = pr("OPEN", [[comment("rev", "Q: why?", review)]])
    result = analyze([merged, open_pr])
    assert result["comments"]["rev"] == Counter({"CR": 1, "FFT": 1, "Q": 1})
    assert result["hedges"]["rev"] == 1 and result["optional"]["rev"] == 1
    assert result["suggestions"]["rev"] == 1
    assert result["cr_verdict"]["rev"] == Counter({"COMMENT": 1})
    assert result["outcomes"]["rev"]["CR"]["accepted"] == 1
    assert result["outcomes"]["rev"]["FFT"]["no_reply"] == 1
    assert result["outcomes"]["rev"]["Q"]["pending"] == 1  # open PR is not "no reply"
    assert result["verdicts"]["rev"] == Counter({"COMMENT": 1, "APPROVED": 1})

    # marked-wrong signal: a `wrong:` tag, a thumbs-down, or "not an issue" in the author's reply
    assert MARKED_WRONG_RE.search("Wrong: this is guarded upstream")
    assert MARKED_WRONG_RE.search("\U0001f44e")
    assert MARKED_WRONG_RE.search("Not an issue here")
    assert not MARKED_WRONG_RE.search("I was wrong, good catch")

    # --json: the seven metrics, per reviewer and per tag, with stable key names
    changes = {"id": "r2", "state": "CHANGES_REQUESTED"}
    judged = pr(
        "MERGED",
        [
            [comment("rev", "NIT: y", review), comment("dev", "\U0001f44e not an issue")],
            [comment("rev", "CR: bad", changes), comment("dev", "Fixed in abc1234")],
        ],
    )
    payload = json.loads(render_json(analyze([merged, open_pr, judged]), ["rev"]))
    metrics = payload["rev"]["metrics"]
    assert tuple(metrics["total"]) == METRIC_KEYS
    assert set(metrics["by_tag"]) == set(TAGS)
    assert all(tuple(row) == METRIC_KEYS for row in metrics["by_tag"].values())
    assert metrics["total"] == {
        "posted": 5, "refuted_by_verifier": None, "accepted": 2, "resolved_by_merge": 1,
        "marked_wrong": 1, "hedges": 1, "cr_as_cr": 1,
    }
    assert metrics["by_tag"]["CR"] == {
        "posted": 2, "refuted_by_verifier": None, "accepted": 2, "resolved_by_merge": 0,
        "marked_wrong": 0, "hedges": 1, "cr_as_cr": 1,
    }
    assert metrics["by_tag"]["NIT"]["marked_wrong"] == 1
    assert metrics["by_tag"]["FFT"]["resolved_by_merge"] == 1
    assert metrics["by_tag"]["untagged"]["posted"] == 0
    assert metrics["not_measured"] == ["refuted_by_verifier"]
    assert payload["rev"]["hedges"] == 1  # keys older consumers read are untouched
    print("self-test ok")


def main():
    parser = argparse.ArgumentParser(description="Review outcomes from GitHub (via gh api graphql).")
    parser.add_argument("repo", nargs="?", help="owner/repo")
    parser.add_argument("--limit", type=int, default=50, help="most recent PRs to read (default 50)")
    parser.add_argument("--since", help="only PRs created on/after YYYY-MM-DD")
    parser.add_argument("--reviewer", help="only this reviewer login")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    parser.add_argument("--self-test", action="store_true", help="offline checks of the classifiers")
    args = parser.parse_args()

    if args.self_test:
        return self_test()
    if not args.repo or "/" not in args.repo:
        parser.error("repo must be owner/repo")
    if args.since and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", args.since):
        parser.error("--since must be YYYY-MM-DD")

    owner, name = args.repo.split("/", 1)
    numbers = list_prs(owner, name, args.limit, args.since)
    prs = [fetch_pr(owner, name, number) for number in numbers]
    result = analyze(prs)

    reviewers = sorted(result["comments"], key=lambda r: -sum(result["comments"][r].values()))
    if args.reviewer:
        reviewers = [r for r in reviewers if r == args.reviewer]
        if not reviewers:
            sys.exit(f"no inline comments by {args.reviewer} in the {len(prs)} PRs read")

    if args.json:
        print(render_json(result, reviewers))
    else:
        print(f"# {args.repo}: {len(prs)} PRs (#{min(numbers)}..#{max(numbers)})\n" if numbers else f"# {args.repo}: no PRs\n")
        print(render(result, reviewers))


if __name__ == "__main__":
    main()
