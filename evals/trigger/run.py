#!/usr/bin/env python3
"""Trigger benchmark: which skill does each prompt actually invoke?

    python3 evals/trigger/run.py                  # 2 runs per query, first tool call
    python3 evals/trigger/run.py --tools 4        # allow up to 4 tool calls before a skill
    python3 evals/trigger/run.py --runs 3 --only q03,q12
    python3 evals/trigger/run.py --score results/<file>.json

Needs a logged-in `claude` (it uses the real config, so the user's own skills
compete, which is the point). Costs model calls: about $0.10-0.40 per run.
EXPERIMENTS-invocation.org has the method and the first results.

Isolation (docs/isolation.org):
  * the plugin is loaded from THIS checkout with --plugin-dir, and every other
    installed copy is disabled by its source key -- read the keys from the init
    message; `guile-skills@synced` was the one a marketplace-name guess missed;
  * --allowedTools Skill, so a run can pick a skill but not act on it;
  * each run is killed at its first Skill call or after --tools calls;
  * the cwd is a throwaway Guile project (irc/ modules, no src/);
  * plugin HOOKS still fire (hooks are not tools), so expect .baseline files
    under the plugin data directory for that scratch project.
"""
import argparse, collections, concurrent.futures as cf, datetime, json, os, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
DISABLE = ["guile-skills@guile-skills", "guile-skills@synced", "guile@guile-skills", "guile@synced"]


def scratch_project():
    d = tempfile.mkdtemp(prefix="trigger-proj.")
    os.makedirs(os.path.join(d, "irc"))
    os.makedirs(os.path.join(d, "tests"))
    with open(os.path.join(d, "irc", "irc.scm"), "w") as f:
        f.write("(define-module (irc irc)\n  #:export (connect))\n(define (connect host) host)\n")
    with open(os.path.join(d, "Makefile"), "w") as f:
        f.write("all:\n\tguild compile irc/irc.scm\n")
    subprocess.run(["git", "init", "-q"], cwd=d, check=True)
    return d


def one(query, run, cwd, max_tools):
    cmd = ["claude", "-p", query["query"], "--output-format", "stream-json", "--verbose",
           "--plugin-dir", ROOT,
           "--settings", json.dumps({"enabledPlugins": {k: False for k in DISABLE}}),
           "--allowedTools", "Skill"]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, cwd=cwd)
    calls, t0 = [], time.time()
    try:
        for line in p.stdout:
            try:
                m = json.loads(line)
            except ValueError:
                continue
            if m.get("type") == "system" and m.get("subtype") == "init":
                ours = [s for s in m.get("skills", []) if s.split(":")[-1] in
                        ("repl-server", "repl-eval", "repl-proxy", "emacs-setup")]
                if len(ours) != len(set(s.split(":")[-1] for s in ours)):
                    calls.append("ABORT:duplicate-plugin-copies " + ",".join(ours))
                    break
            if m.get("type") == "assistant":
                for c in m["message"]["content"]:
                    if c.get("type") == "tool_use":
                        calls.append("skill:" + c["input"].get("skill", "?") if c["name"] == "Skill"
                                     else "tool:" + c["name"])
                if calls and (calls[-1].startswith("skill:") or len(calls) >= max_tools):
                    break
            if m.get("type") == "result" or time.time() - t0 > 150:
                break
    finally:
        p.kill()
    return {"id": query["id"], "run": run, "calls": calls}


def score(bench, results):
    want = {q["id"]: q for q in bench["eval_set"]}
    by = collections.defaultdict(list)
    for r in results:
        skills = [c.split(":")[-1] for c in r["calls"] if c.startswith("skill:")]
        by[r["id"]].append(skills[0] if skills else "none")
    ok = total = 0
    for qid, q in want.items():
        expect = q["expect"].split("|")
        for got in by.get(qid, []):
            total += 1
            ok += got in expect
        print(f"{qid} {q['expect']:24} {by.get(qid)}  | {q['query'][:58]}")
    print(f"\nscore {ok}/{total} = {ok / total:.2f}" if total else "no results")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=2)
    ap.add_argument("--tools", type=int, default=1, help="tool calls allowed before a skill")
    ap.add_argument("--only", default="")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--score", help="score an existing results file and exit")
    a = ap.parse_args()
    bench = json.load(open(os.path.join(HERE, "benchmark.json")))
    if a.score:
        score(bench, json.load(open(a.score)))
        return
    only = set(filter(None, a.only.split(",")))
    queries = [q for q in bench["eval_set"] if not only or q["id"] in only]
    cwd = scratch_project()
    jobs = [(q, r) for q in queries for r in range(a.runs)]
    with cf.ThreadPoolExecutor(a.jobs) as ex:
        results = list(ex.map(lambda j: one(j[0], j[1], cwd, a.tools), jobs))
    out = os.path.join(HERE, "results", f"{datetime.date.today()}-tools{a.tools}.json")
    json.dump(results, open(out, "w"), indent=1)
    print(f"wrote {out}")
    score(bench, results)


if __name__ == "__main__":
    sys.exit(main())
