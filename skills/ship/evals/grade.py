#!/usr/bin/env python3
"""Grade ship eval runs from their stream-json tool-call traces.

Each run is `<case>-<n>.jsonl` (claude -p --output-format stream-json --verbose). The grader
extracts the ordered list of tool calls (Skill / Bash / others) and checks the expectations in
cases.json: a skill was called (min/max), a Bash command matched, or call A came before call B.

A run is INVALID (excluded from the pass rate, reported) when the harness, not the skill under
test, broke it: no output, or a stubbed skill returned an error. Exit 0 only if every valid run
meets every expectation and at least one valid run exists per case.
"""
import argparse
import json
import os
import re
import sys


def load(path):
    events = []
    try:
        for line in open(path, encoding="utf-8", errors="replace"):
            line = line.strip()
            if line.startswith("{"):
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    except OSError:
        return None
    return events


def trace(events):
    """Return (calls, errors, result). calls: [{i, kind, name, text}] in order."""
    calls, results = [], {}
    result = None
    for ev in events:
        t = ev.get("type")
        if t == "assistant":
            for c in ev.get("message", {}).get("content", []) or []:
                if c.get("type") == "tool_use":
                    name, inp = c.get("name", ""), c.get("input", {}) or {}
                    if name == "Skill":
                        skill = str(inp.get("skill", ""))
                        calls.append({"i": len(calls), "kind": "skill", "id": c.get("id"),
                                      "name": skill.split(":")[-1], "text": skill})
                    elif name == "Bash":
                        calls.append({"i": len(calls), "kind": "bash", "id": c.get("id"),
                                      "name": "Bash", "text": str(inp.get("command", ""))})
                    else:
                        calls.append({"i": len(calls), "kind": "other", "id": c.get("id"),
                                      "name": name, "text": ""})
        elif t == "user":
            content = ev.get("message", {}).get("content", [])
            if isinstance(content, list):
                for c in content:
                    if isinstance(c, dict) and c.get("type") == "tool_result":
                        results[c.get("tool_use_id")] = bool(c.get("is_error"))
        elif t == "result":
            result = ev
    return calls, results, result


def first_index(calls, spec):
    for c in calls:
        if "skill" in spec and c["kind"] == "skill" and c["name"] == spec["skill"]:
            return c["i"]
        if "bash" in spec and c["kind"] == "bash" and re.search(spec["bash"], c["text"]):
            return c["i"]
    return None


def check(exp, calls):
    kind = exp["kind"]
    if kind == "skill":
        n = sum(1 for c in calls if c["kind"] == "skill" and c["name"] == exp["name"])
    elif kind == "bash":
        n = sum(1 for c in calls if c["kind"] == "bash" and re.search(exp["pattern"], c["text"]))
    elif kind == "order":
        a, b = first_index(calls, exp["before"]), first_index(calls, exp["after"])
        # Fails when `after` happened and `before` did not happen first.
        return b is None or (a is not None and a < b)
    else:
        raise ValueError(kind)
    return n >= exp.get("min", 0) and (exp.get("max") is None or n <= exp["max"])


def label(calls):
    out = []
    for c in calls:
        if c["kind"] == "skill":
            out.append(c["name"])
        elif c["kind"] == "bash" and re.search(r"\bgh\s+pr\s+create\b", c["text"]):
            out.append("«gh pr create»")
    return " > ".join(out) or "(no skill / pr calls)"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", required=True)
    ap.add_argument("--dir", required=True)
    ap.add_argument("--runs", type=int, required=True)
    ap.add_argument("--only", default="")
    a = ap.parse_args()

    spec = json.load(open(a.cases))
    stubs = set(spec["stubbed_skills"])
    ok = True
    total_cost = 0.0

    for case in spec["cases"]:
        if a.only and not re.search(a.only, case["name"]):
            continue
        print(f"\n== {case['name']} — {case['why']}")
        runs = []
        for n in range(1, a.runs + 1):
            ev = load(os.path.join(a.dir, f"{case['name']}-{n}.jsonl"))
            if not ev:
                runs.append({"n": n, "invalid": "no output"})
                continue
            calls, results, res = trace(ev)
            if res is None:
                runs.append({"n": n, "invalid": "no result event (timeout/crash)", "calls": calls})
                continue
            broke = [c["name"] for c in calls if c["kind"] == "skill" and c["name"] in stubs
                     and results.get(c["id"])]
            if broke:
                runs.append({"n": n, "invalid": f"stub skill error: {','.join(sorted(set(broke)))}", "calls": calls})
                continue
            passed = {e["id"]: check(e, calls) for e in case["expect"]}
            cost = float(res.get("total_cost_usd") or 0)
            total_cost += cost
            runs.append({"n": n, "calls": calls, "passed": passed, "cost": cost,
                         "turns": res.get("num_turns", "?")})

        valid = [r for r in runs if "invalid" not in r]
        print(f"{'EXPECTATION':<34}" + "".join(f"run{r['n']:<4}" for r in runs) + " PASS")
        for e in case["expect"]:
            cells, npass = [], 0
            for r in runs:
                if "invalid" in r:
                    cells.append("  ?   ")
                    continue
                good = r["passed"][e["id"]]
                npass += good
                cells.append("  ✓   " if good else "  ✗   ")
            print(f"{e['id']:<34}" + "".join(cells) + f" {npass}/{len(valid)}")
            ok &= npass == len(valid) and bool(valid)
        if not valid:
            ok = False
        for r in runs:
            if "invalid" in r:
                print(f"run{r['n']}: INVALID — {r['invalid']}")
            else:
                print(f"run{r['n']}: {label(r['calls'])}  | ${r['cost']:.2f}, {r['turns']} turns")

    print(f"\ntotal cost of graded runs: ${total_cost:.2f}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
