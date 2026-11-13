#!/usr/bin/env python3
"""Grade claim-verifier eval outputs: verdict and Basis per labeled claim.

Reads run-N.md files, finds each `### <id>: <verdict>` block, reads its `Basis:` line and
compares both to cases.json. Prints one table per run and a tally. Exit 0 only if every
run matches every label.
"""
import argparse
import glob
import json
import os
import re
import sys

VERDICTS = ("confirmed", "wrong", "weak")
BASES = ("primary", "author-only", "indirect")


def parse(text):
    """Return {id: {"verdict": str|None, "basis": str|None}} for every `### <id>:` block."""
    blocks = {}
    cur = None
    for line in text.splitlines():
        m = re.match(r"^\s*#{3}\s+(\S+?)\s*:\s*(.*)$", line)
        if m:
            found = re.search(r"\b(confirmed|wrong|weak)\b", m.group(2).lower())
            cur = {"verdict": found.group(1) if found else None, "basis": None}
            blocks[m.group(1)] = cur
            continue
        if cur is not None and cur["basis"] is None:
            b = re.match(r"^[\s>*`-]*basis\**\s*:\s*\**\s*(primary|author-only|indirect)\b", line, re.I)
            if b:
                cur["basis"] = b.group(1).lower()
    return blocks


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    cases = json.load(open(args.cases))["cases"]
    files = sorted(glob.glob(os.path.join(args.out, "run-*.md")),
                   key=lambda p: int(re.search(r"run-(\d+)\.md$", p).group(1)))
    if not files:
        print("no run output to grade", file=sys.stderr)
        return 2

    total = good = 0
    for path in files:
        blocks = parse(open(path, errors="replace").read())
        print(f"{os.path.basename(path)}")
        print(f"  {'ID':<4} {'CASE':<30} {'EXPECT':<22} {'GOT':<22} RESULT")
        for c in cases:
            got = blocks.get(c["id"], {"verdict": None, "basis": None})
            want = (c["expect_verdict"], c["expect_basis"])
            have = (got["verdict"], got["basis"])
            ok = want == have
            total += 1
            good += ok
            print(f"  {c['id']:<4} {c['name']:<30} {'%s/%s' % want:<22} "
                  f"{'%s/%s' % (have[0] or 'none', have[1] or 'none'):<22} {'PASS' if ok else 'FAIL'}")
        print()
    print(f"matched {good} / {total}")
    return 0 if good == total else 1


if __name__ == "__main__":
    sys.exit(main())
