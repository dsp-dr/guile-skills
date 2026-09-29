#!/usr/bin/env python3
"""Validate every skills/*/SKILL.md frontmatter before a release can start.

`claude plugin validate' checks the manifest, not a skill's frontmatter, and
`skills-ref validate' needs a cloned repo and a venv, so it has never been wired
into checks (a23284b). This is the part that can run offline, on every PR.

Enforced, with the reason each rule exists:

  name          required; must equal the directory name, because the eval suites
                key off it (tests/validate-evals.py already cross-checks this)
                and kebab-case, because the directory listing rejects otherwise
  description   required; must say WHAT it does and WHEN to use it -- the
                trigger half is what a model matches on. Checked for a "Use
                when/whenever/if" clause and a floor on length
  license       required; an SPDX identifier
  compatibility required since e27e776: the spec's field for stating what the
                skill needs and where it runs
  allowed-tools optional, but if present must be a comma-separated list of known
                tool names, not prose
  metadata      free-form, but `requires.binaries' must be block-style YAML:
                StrictYAML rejects flow sequences, so `binaries: [guile3]' fails
                skills-ref validate (a23284b). Flow style is an error here.

Frontmatter is parsed without PyYAML: it is deliberately simple, and adding a
dependency to a check that must run everywhere is the wrong trade.
"""
import pathlib
import re
import sys

REQUIRED = ("name", "description", "license", "compatibility")
KEBAB = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
TRIGGER = re.compile(r"\bUse (when|whenever|if|for)\b", re.I)
SPDX = {"MIT", "Apache-2.0", "GPL-3.0-or-later", "GPL-3.0-only", "LGPL-3.0-or-later",
        "BSD-2-Clause", "BSD-3-Clause", "ISC", "MPL-2.0", "Unlicense", "CC0-1.0"}
KNOWN_TOOLS = {"Read", "Write", "Edit", "Bash", "Glob", "Grep", "WebFetch",
               "WebSearch", "Task", "TodoWrite", "NotebookEdit"}
FLOW_SEQ = re.compile(r":\s*\[")


def split_frontmatter(text: str) -> tuple[list[str], str] | tuple[None, str]:
    if not text.startswith("---\n"):
        return None, "does not start with a '---' frontmatter fence"
    end = text.find("\n---", 4)
    if end == -1:
        return None, "frontmatter fence is never closed"
    return text[4:end].splitlines(), ""


def top_level(lines: list[str]) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in lines:
        if not line or line.startswith((" ", "\t", "#")):
            continue
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        out[key.strip()] = value.strip()
    return out


def check(skill_md: pathlib.Path) -> list[str]:
    rel = f"{skill_md.parent.name}/SKILL.md"
    lines, err = split_frontmatter(skill_md.read_text())
    if lines is None:
        return [f"{rel}: {err}"]

    errors: list[str] = []
    fields = top_level(lines)

    for key in REQUIRED:
        if key not in fields or not fields[key]:
            errors.append(f"{rel}: missing required frontmatter key {key!r}")

    name = fields.get("name", "")
    if name:
        if name != skill_md.parent.name:
            errors.append(f"{rel}: name {name!r} does not match its directory "
                          f"{skill_md.parent.name!r}")
        if not KEBAB.match(name):
            errors.append(f"{rel}: name {name!r} is not kebab-case")

    desc = fields.get("description", "")
    if desc:
        if len(desc) < 80:
            errors.append(f"{rel}: description is {len(desc)} chars; too short to "
                          "carry both what it does and when to use it")
        if not TRIGGER.search(desc):
            errors.append(f"{rel}: description has no 'Use when/whenever/if' clause, "
                          "so nothing states the trigger a model matches on")

    lic = fields.get("license", "")
    if lic and lic not in SPDX:
        errors.append(f"{rel}: license {lic!r} is not a recognised SPDX identifier")

    tools = fields.get("allowed-tools", "")
    if tools:
        for tool in (t.strip() for t in tools.split(",")):
            if tool and tool not in KNOWN_TOOLS:
                errors.append(f"{rel}: allowed-tools names {tool!r}, which is not a "
                              "known tool")

    for i, line in enumerate(lines, start=2):
        if FLOW_SEQ.search(line):
            errors.append(f"{rel}:{i}: flow-style YAML sequence ({line.strip()!r}); "
                          "StrictYAML rejects it, so skills-ref validate fails")

    return errors


def main() -> int:
    root = pathlib.Path(__file__).resolve().parent.parent
    files = sorted(root.glob("skills/*/SKILL.md"))
    if not files:
        print("no skills/*/SKILL.md found", file=sys.stderr)
        return 1

    all_errors: list[str] = []
    for f in files:
        errors = check(f)
        print(f"  {'ok  ' if not errors else 'FAIL'}  {f.relative_to(root)}")
        all_errors += errors

    sys.stdout.flush()
    if all_errors:
        print(file=sys.stderr)
        for e in all_errors:
            print(f"validate-frontmatter: {e}", file=sys.stderr)
        print(f"\n{len(all_errors)} problem(s) in {len(files)} file(s)", file=sys.stderr)
        return 1

    print(f"\n{len(files)} skill frontmatter block(s) valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
