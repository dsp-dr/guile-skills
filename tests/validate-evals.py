#!/usr/bin/env python3
"""Validate every skills/*/evals/evals.json against the skill-creator schema.

Deterministic and offline: it checks structure, not model behaviour. Model-graded
runs need `claude plugin eval`, which is early access and needs credits, so this
is the part CI can own. See evals/README.org.

Schema (skill-creator references/schemas.md) -- no other keys are permitted:

    {"skill_name": str,
     "evals": [{"id": int, "prompt": str,
                "expected_output": str, "expectations": [str, ...]}]}
"""
import json
import pathlib
import re
import sys

TOP = {"skill_name", "evals"}
EVAL = {"id", "prompt", "expected_output", "expectations"}

# Statements a transcript cannot be checked against. The whole point of an
# expectation is that two readers agree on whether it happened.
VAGUE = re.compile(r"\b(helpful|useful|good|nice|appropriate|reasonable|"
                   r"sensible|properly|correctly handles|as expected)\b", re.I)


def frontmatter_name(skill_md: pathlib.Path) -> str | None:
    text = skill_md.read_text()
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 3)
    if end == -1:
        return None      # fence never closed
    for line in text[3:end].splitlines():
        if line.startswith("name:"):
            return line.split(":", 1)[1].strip()
    return None


def check(path: pathlib.Path) -> list[str]:
    errors = []
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        return [f"{path}: invalid JSON: {exc}"]

    extra = set(data) - TOP
    missing = TOP - set(data)
    if extra:
        errors.append(f"{path}: unexpected top-level keys: {sorted(extra)}")
    if missing:
        errors.append(f"{path}: missing top-level keys: {sorted(missing)}")
        return errors

    skill_md = path.parent.parent / "SKILL.md"
    if skill_md.exists():
        declared = frontmatter_name(skill_md)
        if declared and declared != data["skill_name"]:
            errors.append(f"{path}: skill_name {data['skill_name']!r} does not match "
                          f"{skill_md}'s frontmatter name {declared!r}")
    else:
        errors.append(f"{path}: no SKILL.md beside it at {skill_md}")

    evals = data["evals"]
    if not isinstance(evals, list) or not evals:
        errors.append(f"{path}: evals must be a non-empty list")
        return errors
    if not 3 <= len(evals) <= 4:
        errors.append(f"{path}: {len(evals)} evals; the house range is 3 to 4")

    for index, item in enumerate(evals):
        where = f"{path} eval[{index}]"
        if not isinstance(item, dict):
            errors.append(f"{where}: is a {type(item).__name__}, not an object")
            continue
        bad = set(item) - EVAL
        gone = EVAL - set(item)
        if bad:
            errors.append(f"{where}: unexpected keys: {sorted(bad)}")
        if gone:
            errors.append(f"{where}: missing keys: {sorted(gone)}")
            continue
        if item["id"] != index + 1:
            errors.append(f"{where}: id is {item['id']}, expected {index + 1} "
                          "(ids start at 1 and run consecutively)")
        for field in ("prompt", "expected_output"):
            if not isinstance(item[field], str) or not item[field].strip():
                errors.append(f"{where}: {field} must be a non-empty string")
        exps = item["expectations"]
        if not isinstance(exps, list) or not exps:
            errors.append(f"{where}: expectations must be a non-empty list")
            continue
        for e in exps:
            if not isinstance(e, str) or not e.strip():
                errors.append(f"{where}: an expectation is empty or not a string")
            elif VAGUE.search(e):
                errors.append(f"{where}: expectation is not transcript-checkable "
                              f"({VAGUE.search(e).group(0)!r}): {e[:70]}...")
    return errors


def main() -> int:
    root = pathlib.Path(__file__).resolve().parent.parent
    files = sorted(root.glob("skills/*/evals/evals.json"))
    if not files:
        print("validate-evals: no skills/*/evals/evals.json found", file=sys.stderr)
        return 1

    all_errors = []
    for f in files:
        errors = check(f)
        rel = f.relative_to(root)
        count = len(json.loads(f.read_text()).get("evals", [])) if not errors else "?"
        print(f"  {'ok  ' if not errors else 'FAIL'}  {rel}  ({count} evals)")
        all_errors += errors

    sys.stdout.flush()
    if all_errors:
        print(file=sys.stderr)
        for e in all_errors:
            print(f"validate-evals: {e}", file=sys.stderr)
        print(f"\n{len(all_errors)} problem(s) in {len(files)} file(s)", file=sys.stderr)
        return 1

    print(f"\n{len(files)} eval suite(s) valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
