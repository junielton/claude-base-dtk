#!/usr/bin/env python3
"""Grade review-peer eval reports: which bucket did each labeled finding land in.

Reads run-N.md files, parses the 🔴 / 🟡 / 💬 sections into findings (### headings),
matches each expectation in cases.json against them, prints the bucket per run and a tally.
Exit 0 only if every run matches every expectation.
"""
import argparse
import json
import re
import sys

BUCKETS = ("blocking", "non-blocking", "question")


def bucket_of(heading):
    h = heading.lower()
    if "non-blocking" in h or "🟡" in heading:
        return "non-blocking"
    if "blocking" in h or "🔴" in heading:
        return "blocking"
    if "question" in h or "💬" in heading:
        return "question"
    return None


def parse(text):
    """Return [{bucket, heading, text}] for every ### finding under a severity section."""
    findings, bucket, cur = [], None, None
    for line in text.splitlines():
        if re.match(r"^##\s", line):
            bucket, cur = bucket_of(line), None
        elif re.match(r"^###\s", line) and bucket:
            cur = {"bucket": bucket, "heading": line.lstrip("# ").strip(), "text": line}
            findings.append(cur)
        elif cur is not None:
            cur["text"] += "\n" + line
    return findings


def matches(exp, f):
    if not re.search(exp["file"], f["heading"], re.I):
        return False
    hay = f["heading"] if exp["scope"] == "heading" else f["text"]
    return re.search(exp["keywords"], hay, re.I) is not None


def passed(exp, got):
    want = exp["expect"]
    if want == "absent":
        return not got
    if want == "absent-or-question":
        return all(b == "question" for b in got)
    return bool(got) and all(b == want for b in got)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", required=True)
    ap.add_argument("--dir", required=True)
    ap.add_argument("--runs", type=int, required=True)
    a = ap.parse_args()

    exps = json.load(open(a.cases))["expectations"]
    runs = []
    for n in range(1, a.runs + 1):
        try:
            findings = parse(open(f"{a.dir}/run-{n}.md").read())
        except OSError:
            findings = None
        runs.append(findings)

    ok = True
    print(f"{'EXPECTATION':<34} {'EXPECT':<19} " + " ".join(f"{'run'+str(n):<13}" for n in range(1, a.runs + 1)) + " PASS")
    print("-" * (56 + 14 * a.runs))
    for e in exps:
        cells, npass = [], 0
        for findings in runs:
            if findings is None:
                cells.append("NO_OUTPUT")
                continue
            got = [f["bucket"] for f in findings if matches(e, f)]
            label = "+".join(sorted(set(got))) if got else "absent"
            good = passed(e, got)
            npass += good
            cells.append(label + ("" if good else " ✗"))
        ok &= npass == a.runs
        print(f"{e['name']:<34} {e['expect']:<19} " + " ".join(f"{c:<13}" for c in cells) + f" {npass}/{a.runs}")

    print()
    for n, findings in enumerate(runs, 1):
        if findings is None:
            print(f"run{n}: no output")
            continue
        counts = {b: sum(f["bucket"] == b for f in findings) for b in BUCKETS}
        known = [f for f in findings if any(matches(e, f) for e in exps)]
        extra = [f for f in findings if f not in known]
        print(f"run{n}: {counts['blocking']} blocking / {counts['non-blocking']} non-blocking / {counts['question']} questions"
              f" — unlabeled: " + ("; ".join(f"[{f['bucket']}] {f['heading'][:60]}" for f in extra) or "none"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
