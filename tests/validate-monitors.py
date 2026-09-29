#!/usr/bin/env python3
"""Validate monitors/monitors.json against the plugin manifest reference.

This exists because `claude plugin validate' does not. Measured 2026-09-29 with
the file at the default path and again declared explicitly as
`experimental.monitors': an unknown key, a missing `description' and a `when' of
"sometimes" all passed, with and without --strict. The reference says a monitor
entry is strict and that an unknown key inside one means the plugin does not
load, so the CLI's silence is not reassurance -- it is no coverage at all.

Schema (manifest-reference, fetched 2026-09-28) -- a monitor entry is strict:

    [{"name": str,          # required, unique within the plugin
      "command": str,       # required, must not reference ${user_config.*}
      "description": str,   # required
      "when": str}]         # optional: "always" | "on-skill-invoke:<skill>"

Two checks beyond the reference, because both are silent failures:
  - on-skill-invoke names a skill that must actually exist in skills/
  - a command referencing ${CLAUDE_PLUGIN_ROOT}/<path> must point at a real file
"""
import json
import pathlib
import re
import sys

ENTRY = {"name", "command", "description", "when"}
REQUIRED = {"name", "command", "description"}
WHEN = re.compile(r"^(always|on-skill-invoke:.+)$")
USER_CONFIG = re.compile(r"\$\{user_config\.")
PLUGIN_ROOT_REF = re.compile(r"\$\{CLAUDE_PLUGIN_ROOT\}/([^\"'\s]+)")


def check(path: pathlib.Path, root: pathlib.Path) -> list[str]:
    errors: list[str] = []
    try:
        doc = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        return [f"{path}: not valid JSON: {exc}"]

    if not isinstance(doc, list):
        return [f"{path}: top level must be an array of monitor entries"]
    if not doc:
        return [f"{path}: no monitor entries; delete the file instead"]

    skills = {p.name for p in (root / "skills").iterdir()
              if (p / "SKILL.md").is_file()} if (root / "skills").is_dir() else set()
    seen: dict[str, int] = {}

    for i, entry in enumerate(doc):
        where = f"{path}[{i}]"
        if not isinstance(entry, dict):
            errors.append(f"{where}: entry must be an object")
            continue

        for key in REQUIRED - entry.keys():
            errors.append(f"{where}: missing required key {key!r}")
        for key in entry.keys() - ENTRY:
            errors.append(f"{where}: unknown key {key!r} -- an entry is strict, "
                          "so this stops the whole plugin loading")
        for key in REQUIRED & entry.keys():
            if not isinstance(entry[key], str) or not entry[key].strip():
                errors.append(f"{where}: {key!r} must be a non-empty string")

        name = entry.get("name")
        if isinstance(name, str):
            if name in seen:
                errors.append(f"{where}: name {name!r} already used at index {seen[name]}"
                              " -- names must be unique within the plugin")
            seen[name] = i

        command = entry.get("command")
        if isinstance(command, str):
            if USER_CONFIG.search(command):
                errors.append(f"{where}: command references ${{user_config.*}}, "
                              "which a monitor command may not do")
            for rel in PLUGIN_ROOT_REF.findall(command):
                if not (root / rel).exists():
                    errors.append(f"{where}: command points at {rel!r}, "
                                  "which does not exist in the plugin root")

        when = entry.get("when")
        if when is not None:
            if not isinstance(when, str) or not WHEN.match(when):
                errors.append(f"{where}: when must be 'always' or "
                              f"'on-skill-invoke:<skill>', not {when!r}")
            elif when.startswith("on-skill-invoke:"):
                skill = when.split(":", 1)[1]
                if skills and skill not in skills:
                    errors.append(f"{where}: when names skill {skill!r}, which is not "
                                  f"in skills/ ({', '.join(sorted(skills)) or 'none'})")

    return errors


def main() -> int:
    root = pathlib.Path(__file__).resolve().parent.parent
    path = root / "monitors" / "monitors.json"

    if not path.exists():
        print("no monitors/monitors.json; nothing to validate.")
        return 0

    errors = check(path, root)
    count = len(json.loads(path.read_text())) if not errors else "?"
    print(f"  {'ok  ' if not errors else 'FAIL'}  {path.relative_to(root)}  ({count} monitors)")

    sys.stdout.flush()
    if errors:
        print(file=sys.stderr)
        for e in errors:
            print(f"validate-monitors: {e}", file=sys.stderr)
        print(f"\n{len(errors)} problem(s)", file=sys.stderr)
        return 1

    print("\nmonitor entries valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
