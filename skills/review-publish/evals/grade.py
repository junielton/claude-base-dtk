#!/usr/bin/env python3
"""Grades one review-publish eval run.

Reads the publish-N.json the skill produced inside a run directory and checks it
against the case's expectations. Prints one JSON object; exit 0 iff every check passed.

Usage: grade.py --cases cases.json --case a --run-dir DIR --lint tone-lint.sh
"""
import argparse
import glob
import json
import os
import subprocess
import sys


def load_payload(run_dir):
    found = sorted(
        p
        for p in glob.glob(os.path.join(run_dir, "memories", "reviews", "PR-*", "publish-*.json"))
        if not p.endswith(".dropped.json")
    )
    if not found:
        return None, None, "no publish-N.json was written"
    try:
        with open(found[-1], encoding="utf-8") as fh:
            return found[-1], json.load(fh), ""
    except (OSError, ValueError) as err:
        return found[-1], None, f"publish-N.json is not valid JSON: {err}"


def anchor(comment):
    return f"{comment.get('path')}:{comment.get('line')}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", required=True)
    ap.add_argument("--case", required=True)
    ap.add_argument("--run-dir", required=True)
    ap.add_argument("--lint", required=True)
    args = ap.parse_args()

    with open(args.cases, encoding="utf-8") as fh:
        spec = json.load(fh)
    case = next(c for c in spec["cases"] if c["id"] == args.case)

    checks = {}

    def record(name, ok, detail=""):
        checks[name] = {"pass": bool(ok), "detail": detail}

    path, payload, err = load_payload(args.run_dir)
    record("payload", payload is not None and payload.get("commit_id") == spec["head_sha"],
           err or ("commit_id is not the PR head" if payload and payload.get("commit_id") != spec["head_sha"] else ""))

    if payload is None:
        for name in ("verdict", "lint", "anchors", "no-leak"):
            record(name, False, "no payload")
        if case.get("expect_suggestion_on"):
            record("suggestion", False, "no payload")
    else:
        comments = payload.get("comments") or []
        texts = [payload.get("body") or ""] + [c.get("body") or "" for c in comments]

        record("verdict", payload.get("event") == case["expect_event"],
               f"event={payload.get('event')} expected={case['expect_event']}")

        if os.path.isfile(args.lint):
            res = subprocess.run(["bash", args.lint, "--payload", path], capture_output=True, text=True)
            record("lint", res.returncode == 0, res.stderr.strip().replace("\n", " | "))
        else:
            record("lint", False, f"tone-lint.sh not found at {args.lint}")

        got = sorted(anchor(c) for c in comments)
        want = sorted(case["expect_findings"])
        record("anchors", got == want, f"got={got} want={want}")

        hay = "\n".join(texts).lower()
        leaked = [p for p in case.get("leak_phrases", []) if p.lower() in hay]
        record("no-leak", not leaked, f"leaked={leaked}" if leaked else "")

        target = case.get("expect_suggestion_on")
        if target:
            hit = [c for c in comments if anchor(c) == target]
            record("suggestion", bool(hit) and "```suggestion" in (hit[0].get("body") or ""),
                   f"no suggestion block on {target}")

    # The skill must have reached the dry run and left it clean.
    calls = os.path.join(args.run_dir, "post-review.calls")
    last = None
    if os.path.isfile(calls):
        with open(calls, encoding="utf-8") as fh:
            lines = [l.strip() for l in fh if l.strip()]
        last = lines[-1] if lines else None
    record("dry-run", last == "exit=0", f"last post-review run: {last or 'never ran'}")

    result = {"case": args.case, "pass": all(c["pass"] for c in checks.values()), "checks": checks}
    print(json.dumps(result))
    sys.exit(0 if result["pass"] else 1)


if __name__ == "__main__":
    main()
