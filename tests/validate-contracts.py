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

guile-json is not in the FreeBSD package list either: `pkg search guile' returns
guile-lib, guile-cairo, g-golf, slib and the interpreters, no guile-json.

But that turns out not to matter, measured 2026-09-29 against guile-json 4.7.3:
it is PURE SCHEME -- eleven .scm files, no C -- so it needs no build and no
install. Adding its checkout to the load path is enough:

    guile3 -L /path/to/guile-json -c '(use-modules (json)) ...'

Verified: it round-trips ({"a":[1,2,{"b":true}]} parses to
(("a" . #(1 2 (("b" . #t))))), objects as alists and arrays as vectors), and it
parses all three of this plugin's operational files -- plugin.json, hooks.json and
monitors.json. So the dependency is a vendored directory or a submodule plus one
-L flag, not a port and not a build step.

Three options, none free:

  1. Depend on guile-json (4.7.3). Now the cheapest option, not the most expensive:
     pure Scheme, no build, no package required -- vendor it or add a submodule and
     pass -L. Verified working on this cell against all three operational files.
  2. Write a small reader for the subset we need. These files are machine-generated
     and shallow: objects, arrays, strings, numbers, booleans, null, no exotic
     escapes. A reader for that is perhaps 80 lines of Scheme and needs no
     dependency -- but it is a JSON parser we now maintain, and a wrong one would
     make every contract claim suspect.
  3. Keep the readers in Python and port only the RULES to Scheme, with Python
     handing over an s-expression. Splits the tool in two for no obvious gain.

Option 1 is now the likely one, on the strength of that measurement: writing our
own reader (option 2) was only attractive while the dependency looked expensive,
and a JSON parser we maintain ourselves is a liability -- one that silently
mis-parses makes every `ok' it prints a lie. Whichever is chosen still arrives with
its own planted-fault calibration before anything depends on it.

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
#
# `$schema' is deliberately NOT in this list, and the first version of it was wrong
# to include it. Measured on 2.1.261: a manifest carrying
# "$schema": "https://www.schemastore.org/claude-code-plugin-manifest.json" passes
# `validate --strict' clean, and the binary describes the field as "JSON Schema
# reference for editor autocomplete/validation; ignored at load time". Anthropic's
# own .claude-plugin/marketplace.json sets it. So it is a first-class optional field
# whose whole purpose is editor validation -- forbidding it made this check reject a
# legal, useful file, which is a worse failure than the one it was guarding against.
#
# What remains forbidden is metadata about OUR process: a contract version, when we
# measured it, what we concluded. That belongs in contracts/ because an unknown key
# in a strict entry stops the plugin loading and an unknown top-level manifest key
# fails --strict.
CONTRACT_KEYS = re.compile(
    r'"(?:_comment|contract|contract_version|contractVersion|schema_version|'
    r'schemaVersion|measured_on|measured_faults|cli_validates|'
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
