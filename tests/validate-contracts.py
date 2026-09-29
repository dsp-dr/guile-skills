#!/usr/bin/env python3
"""Fail when the product's contract may have moved, and when a contract leaks.

Two jobs, and the second is the one that protects future agents.

1. DRIFT. contracts/cell.json pins the Claude Code CLI these contracts were
   measured against. If the installed CLI differs, every claim in
   contracts/artifacts.json is unverified on this version -- including "monitors
   are not validated at all", which is the kind of claim that ages badly. The
   validator fails and asks for a re-measure rather than letting stale evidence
   pass as current.

2. ISOLATION. The operational files -- the ones Claude Code actually reads -- must
   carry no contract metadata. An unknown key inside a strict entry stops the
   plugin loading, and an unknown top-level manifest key is stripped with a warning
   that fails --strict. So a well-meant `"contract_version": "1"` in
   monitors/monitors.json would break the plugin, and a `$schema` or provenance
   comment in plugin.json would break --strict. This check makes that a test
   failure instead of a field report.

Neither job needs the network.

WIP: this belongs in Guile, and here is what stands in the way
------------------------------------------------------------
Python is the right choice for the FIRST version of a tool -- it is already a
dependency of this repo's checks and it has the JSON reader built in. But a plugin
for driving Guile projects whose own tooling is Python is not dogfooding anything,
and these validators are exactly the kind of small, pure, well-specified job that
should be written in the language the plugin exists to support.

The blocker is concrete, measured on nexus 2026-09-29:

    guile3 -c '(use-modules (json))'
    => no code for module (json)

Guile 3.0.10's core has no JSON reader, checked exhaustively: (json), (json parser),
(ice-9 json), (web json), (sxml json) and (guile-json) are all absent, nothing under
/usr/local/share/guile or /usr/local/lib/guile is named for JSON, and GUILE_LOAD_PATH
is unset. `ls /usr/local/share/guile/3.0/' offers `web' and `sxml' and nothing else
relevant.

Worse for option 1 below: guile-json is not merely uninstalled, it is not in the
FreeBSD package list at all. `pkg search guile' returns guile-lib, guile-cairo,
g-golf, slib and the interpreters -- no guile-json -- so depending on it means
building from source on this platform, and CI installs guile-3.0 only.

Three options, none free:

  1. Depend on guile-json. Cleanest code, but it is not packaged for FreeBSD, so it
     means building from source on the machine this repo is developed on.
  2. Write a small reader for the subset we need. These files are machine-generated
     and shallow: objects, arrays, strings, numbers, booleans, null, no exotic
     escapes. A reader for that is perhaps 80 lines of Scheme and needs no
     dependency -- but it is a JSON parser we now maintain, and a wrong one would
     make every contract claim suspect.
  3. Keep the readers in Python and port only the RULES to Scheme, with Python
     handing over an s-expression. Splits the tool in two for no obvious gain.

Option 2 is the most likely, and it should arrive with its own planted-fault
calibration before anything depends on it -- a JSON reader that silently
mis-parses is worse than no validator, because every `ok' it prints is a lie.

Scope for v0 when it comes: keep the schemas SIMPLE. Only the keys these files
actually use, with the shapes already recorded in contracts/artifacts.json. Not a
general JSON Schema engine, and not a transcription of every optional field in the
manifest reference -- the contract we can check is the one we can also calibrate.
"""
import json
import pathlib
import re
import subprocess
import sys

# Vocabulary that belongs in contracts/ and nowhere else.
CONTRACT_KEYS = re.compile(
    r'"(?:_comment|contract|contract_version|contractVersion|schema_version|'
    r'schemaVersion|\$schema|measured_on|measured_faults|cli_validates|'
    r'validated_by|manifest_reference\w*)"'
)

OPERATIONAL = [
    ".claude-plugin/plugin.json",
    "hooks/hooks.json",
    "monitors/monitors.json",
]


def live_cli_version() -> str | None:
    try:
        out = subprocess.run(["claude", "--version"], capture_output=True,
                             text=True, timeout=30).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    m = re.search(r"\d+\.\d+\.\d+", out)
    return m.group(0) if m else None


def check_drift(root: pathlib.Path) -> list[str]:
    cell_path = root / "contracts" / "cell.json"
    if not cell_path.exists():
        return [f"{cell_path.relative_to(root)} is missing; nothing pins the contract"]
    cell = json.loads(cell_path.read_text())
    pinned = cell.get("claude_cli")
    live = live_cli_version()
    if live is None:
        print("  ..    claude CLI not on PATH; drift check skipped")
        return []
    if pinned != live:
        return [
            f"contract drift: contracts/cell.json pins claude_cli {pinned!r} but "
            f"{live!r} is installed. Every claim in contracts/artifacts.json is "
            "unverified on this version -- re-measure the planted faults listed "
            "there, then update cell.json. Do not just bump the number."
        ]
    print(f"  ok    contract cell matches the installed CLI ({live})")
    return []


def check_shape(root: pathlib.Path) -> list[str]:
    art_path = root / "contracts" / "artifacts.json"
    if not art_path.exists():
        return [f"{art_path.relative_to(root)} is missing"]
    errors = []
    for a in json.loads(art_path.read_text())["artifacts"]:
        rel = a["file"]
        if "*" in rel:
            continue                      # globbed artifacts have their own validators
        f = root / rel
        if not f.exists():
            continue                      # an artifact this branch does not have yet
        required = a.get("required_top_level")
        if not isinstance(required, list):
            continue                      # prose, e.g. "an array of monitor entries"
        try:
            doc = json.loads(f.read_text())
        except json.JSONDecodeError as exc:
            errors.append(f"{rel}: not valid JSON: {exc}")
            continue
        if not isinstance(doc, dict):
            errors.append(f"{rel}: expected an object at the top level")
            continue
        for key in required:
            if key not in doc:
                errors.append(f"{rel}: contract requires top-level {key!r}, which is absent")
        if not errors:
            print(f"  ok    {rel} has the contracted top-level shape")
    return errors


def check_isolation(root: pathlib.Path) -> list[str]:
    errors = []
    for rel in OPERATIONAL:
        f = root / rel
        if not f.exists():
            continue
        text = f.read_text()
        for m in CONTRACT_KEYS.finditer(text):
            line = text[:m.start()].count("\n") + 1
            errors.append(
                f"{rel}:{line}: {m.group(0)} is contract metadata and must not appear "
                "in a file Claude Code reads -- it belongs in contracts/. An unknown "
                "key in a strict entry stops the plugin loading."
            )
    if not errors:
        print(f"  ok    no contract metadata leaked into {len(OPERATIONAL)} operational file(s)")
    return errors


def main() -> int:
    root = pathlib.Path(__file__).resolve().parent.parent
    errors = check_drift(root) + check_shape(root) + check_isolation(root)
    sys.stdout.flush()
    if errors:
        print(file=sys.stderr)
        for e in errors:
            print(f"validate-contracts: {e}", file=sys.stderr)
        print(f"\n{len(errors)} problem(s)", file=sys.stderr)
        return 1
    print("\ncontracts hold.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
