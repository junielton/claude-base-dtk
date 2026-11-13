#!/usr/bin/env python3
"""Grade pr-story eval runs.

For every <work>/<case>/run-N/ folder it finds the cached story written by the skill
(<run>/data/dtk/stories/<owner>/<repo>/PR-<n>.md) and checks four things:

  1. gate      scripts/pr-story/check-story.sh exits 0 on the story.
  2. links     every github.com link in the story resolves through `gh` (no 404).
  3. verifier  a fresh dtk:claim-verifier run on up to 8 sentences sampled from the story
               returns no `wrong`.
  4. author    every sentence the verifier marks `Basis: author-only` names the PR author.

A case marked "large" also reports whether a fact-gathering subagent ran (a subagent other
than claim-verifier and link-finder). That one is printed, not graded: the transcript shows it
only when the model chose to delegate, and the 25-file rule is the skill's, not this grader's.

Exit 0 only when every run passes checks 1 to 4.
"""
import argparse
import glob
import json
import os
import random
import re
import subprocess
import sys
import tempfile

MAX_CLAIMS = 8
VERIFIER_TIMEOUT = 600


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


# ---------------------------------------------------------------- story reading

def split_story(text):
    """Return (frontmatter dict, body) for a story file."""
    fm, body = {}, text
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
    if m:
        for line in m.group(1).splitlines():
            k, _, v = line.partition(":")
            fm[k.strip()] = v.strip()
        body = m.group(2)
    return fm, body


def sentences(body):
    """Candidate claims: sentences of paragraphs and bullets, links reduced to their text."""
    out = []
    for raw in body.splitlines():
        line = raw.strip()
        if not line or line.startswith(("###", "*Feature", "*Fix", "*Chore")) or re.match(r"^\*[^*].*\[PR #", line):
            continue
        if re.match(r"^\*\*(What changes for you|Left open)\*\*$", line):
            continue
        line = re.sub(r"^[-*]\s+", "", line)
        line = re.sub(r"\*\*Why:\*\*\s*", "", line)
        line = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", line)
        line = line.replace("**", "").replace("`", "")
        for s in re.split(r"(?<=[.!?])\s+(?=[A-Z\"'(])", line):
            s = s.strip()
            if len(s) >= 40 and s.lower() != "nothing.":
                out.append(s)
    return out


# ---------------------------------------------------------------- links

LINK_RE = re.compile(r"\]\((https?://github\.com/[^)\s]+)\)")


def check_link(url):
    """Return (ok, how). Unrecognised github.com shapes are reported as unchecked, not failed."""
    m = re.match(r"https?://github\.com/([^/]+)/([^/]+)/(.*)$", url)
    if not m:
        return None, "not a repo link"
    owner, repo, rest = m.groups()
    repo_slug = f"{owner}/{repo}"
    rest = re.split(r"[?]", rest)[0]
    frag = ""
    if "#" in rest:
        rest, frag = rest.split("#", 1)
    parts = rest.split("/")
    cmd = None
    if parts[0] == "pull" and len(parts) >= 2 and parts[1].isdigit():
        if frag.startswith("discussion_r"):
            cmd = ["gh", "api", f"repos/{repo_slug}/pulls/comments/{frag[len('discussion_r'):]}"]
        elif frag.startswith("issuecomment-"):
            cmd = ["gh", "api", f"repos/{repo_slug}/issues/comments/{frag[len('issuecomment-'):]}"]
        else:
            cmd = ["gh", "pr", "view", parts[1], "-R", repo_slug]
    elif parts[0] in ("blob", "tree") and len(parts) >= 3:
        ref, path = parts[1], "/".join(parts[2:])
        cmd = ["gh", "api", f"repos/{repo_slug}/contents/{path}?ref={ref}"]
    elif parts[0] == "commit" and len(parts) >= 2:
        cmd = ["gh", "api", f"repos/{repo_slug}/commits/{parts[1]}"]
    elif parts[0] == "actions" and len(parts) >= 3 and parts[1] == "runs":
        cmd = ["gh", "run", "view", parts[2], "-R", repo_slug]
    elif parts[0] == "issues" and len(parts) >= 2 and parts[1].isdigit():
        cmd = ["gh", "issue", "view", parts[1], "-R", repo_slug]
    if cmd is None:
        return None, "unrecognised shape"
    r = sh(cmd)
    return r.returncode == 0, " ".join(cmd[:3])


# ---------------------------------------------------------------- verifier

def parse_verdicts(text):
    """{id: {"verdict", "basis"}} from `### <id>: <verdict>` blocks with a `Basis:` line."""
    blocks, cur = {}, None
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


def verify(claims, case, ref, root, model):
    agent = os.path.join(root, "agents", "claim-verifier.md")
    with open(agent) as f:
        parts = re.split(r"^---\s*$", f.read(), maxsplit=2, flags=re.M)
    body = parts[2] if len(parts) == 3 else parts[-1]
    lines = ["Verify this batch of claims.", "", "Context:",
             f"repo: {case['repo']}", f"ref: {ref}", "clone: no", ""]
    for i, c in enumerate(claims, 1):
        lines += [f"id: s{i}", f"claim: {c}",
                  f"hints: pull request #{case['number']} of {case['repo']}, read at {ref}", ""]
    with tempfile.TemporaryDirectory() as sandbox, tempfile.NamedTemporaryFile("w", suffix=".md") as sp:
        sp.write(body)
        sp.flush()
        cmd = ["claude", "-p", "\n".join(lines), "--append-system-prompt-file", sp.name,
               "--allowed-tools", "Read", "Grep", "Glob", "Bash(gh:*)", "Bash(git:*)",
               "Bash(jq:*)", "Bash(base64:*)"]
        if model:
            cmd += ["--model", model]
        env = {k: v for k, v in os.environ.items() if k not in ("CLAUDECODE", "CLAUDE_CODE_SSE_PORT")}
        try:
            r = subprocess.run(cmd, cwd=sandbox, env=env, capture_output=True, text=True, timeout=VERIFIER_TIMEOUT)
        except subprocess.TimeoutExpired:
            return None
    return r.stdout


# ---------------------------------------------------------------- transcript

def helper_subagents(transcript):
    """subagent_type of every Agent/Task call in a stream-json transcript."""
    seen = []
    if not os.path.exists(transcript):
        return seen
    for line in open(transcript, errors="replace"):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if d.get("type") != "assistant":
            continue
        for b in d.get("message", {}).get("content", []):
            if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") in ("Agent", "Task"):
                seen.append((b.get("input") or {}).get("subagent_type") or "general-purpose")
    return seen


# ---------------------------------------------------------------- grading

def grade_run(run_dir, case, root, model):
    """Return (list of (check, ok, detail), notes)."""
    checks, notes = [], []
    story_files = glob.glob(os.path.join(run_dir, "data", "dtk", "stories", "*", "*", f"PR-{case['number']}.md"))
    if not story_files:
        return [("gate", False, "no story in the cache: the skill did not save one")], notes
    story = story_files[0]

    gate = sh(["bash", os.path.join(root, "scripts", "pr-story", "check-story.sh"), story])
    checks.append(("gate", gate.returncode == 0, (gate.stdout or gate.stderr).strip().replace("\n", " | ")))

    text = open(story, errors="replace").read()
    fm, body = split_story(text)

    urls = sorted(set(LINK_RE.findall(body)))
    broken = []
    for u in urls:
        ok, how = check_link(u)
        if ok is None:
            notes.append(f"unchecked link ({how}): {u}")
        elif not ok:
            broken.append(u)
    checks.append(("links", not broken and bool(urls),
                   f"{len(urls)} github.com links" + (f", broken: {broken}" if broken else "")
                   if urls else "the story has no github.com link"))

    cands = sentences(body)
    rng = random.Random(case["number"])
    picked = rng.sample(cands, min(MAX_CLAIMS, len(cands)))
    out = verify(picked, case, case["ref"], root, model) if picked else ""
    if out is None:
        checks.append(("verifier", False, "the verifier timed out"))
        checks.append(("author", False, "no verifier output"))
    else:
        verdicts = parse_verdicts(out)
        missing = [f"s{i}" for i in range(1, len(picked) + 1) if f"s{i}" not in verdicts]
        wrong = [f"s{i}" for i in range(1, len(picked) + 1) if verdicts.get(f"s{i}", {}).get("verdict") == "wrong"]
        detail = f"{len(picked)} sentences checked"
        if wrong:
            detail += "; wrong: " + "; ".join(f"{w} '{picked[int(w[1:]) - 1][:90]}'" for w in wrong)
        if missing:
            detail += f"; no verdict for {missing}"
        checks.append(("verifier", bool(picked) and not wrong and not missing, detail))

        unattributed = []
        for i, s in enumerate(picked, 1):
            v = verdicts.get(f"s{i}", {})
            if v.get("basis") == "author-only" and case["author"].lower() not in s.lower():
                unattributed.append(s[:90])
        checks.append(("author", not unattributed,
                       "every author-only sentence names the author" if not unattributed
                       else "does not name the author: " + "; ".join(unattributed)))

    if case.get("large"):
        helpers = [h for h in helper_subagents(os.path.join(run_dir, "transcript.jsonl"))
                   if h not in ("dtk:claim-verifier", "dtk:link-finder")]
        notes.append("fact-gathering subagent: " + ("yes (%s)" % ", ".join(helpers) if helpers else "NOT seen"))
    return checks, notes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", required=True)
    ap.add_argument("--work", required=True)
    ap.add_argument("--root", required=True)
    ap.add_argument("--model", default="")
    ap.add_argument("--only", default="")
    args = ap.parse_args()

    cases = [c for c in json.load(open(args.cases))["cases"] if not args.only or c["id"] == args.only]
    total = good = 0
    for case in cases:
        runs = sorted(glob.glob(os.path.join(args.work, case["id"], "run-*")),
                      key=lambda p: int(p.rsplit("-", 1)[1]))
        if not runs:
            print(f"{case['id']}: no run output to grade", file=sys.stderr)
            return 2
        for run in runs:
            checks, notes = grade_run(run, case, args.root, args.model)
            ok = all(c[1] for c in checks)
            total += 1
            good += ok
            print(f"{case['id']} / {os.path.basename(run)}  ({case['pr']})  {'PASS' if ok else 'FAIL'}")
            for name, passed, detail in checks:
                print(f"  {'ok  ' if passed else 'FAIL'} {name:<9} {detail}")
            for n in notes:
                print(f"  note {n}")
            print()
    print(f"passed {good} / {total}")
    return 0 if good == total else 1


if __name__ == "__main__":
    sys.exit(main())
