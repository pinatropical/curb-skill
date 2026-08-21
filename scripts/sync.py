#!/usr/bin/env python3
"""Generate every derived file in this repo from its single source, and refuse
to let the copies drift.

Five runtimes read five different manifests and two command formats. Keeping
them the same by hand does not work: by the time this script was written the
four `commands/*.toml` files had already gained three improvements that the
`commands/*.md` files they were copied from never got back.

    scripts/sync.py            rewrite every derived file
    scripts/sync.py --check    exit 1 if any derived file is out of date
    scripts/sync.py --check --online
                               additionally re-fetch the Agent Plugins schema
                               instead of trusting the field list baked in here

Sources of truth, and what is derived from each:

    plugin.json                 name, version, description, author, homepage,
                                repository, license, keywords
      -> .claude-plugin/plugin.json        all of them
      -> .claude-plugin/marketplace.json   description, version
      -> .codex-plugin/plugin.json         all of them; `interface` is Codex's
                                           own and is preserved untouched
      -> .cursor-plugin/plugin.json        the subset Cursor documents
      -> gemini-extension.json             name, version, description
      -> skills/curb-sale/SKILL.md         metadata.version only

    commands/<n>.md             the prompt, written once
      -> commands/<n>.toml      the same prompt for Gemini CLI, which reads
                                only .toml, with `$ARGUMENTS` -> {{args}}

    agents-snippet.md           the paste-in block
      -> README.md              its byte count, quoted in prose

Nothing else in the repo is generated. `skills/curb-sale/**` is written by
hand and read by every runtime unchanged.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Agent Plugins 1.0.0 is a closed schema: additionalProperties is false and the
# permitted top-level fields are exactly these. Baked in so --check works with
# no network; --online re-fetches and compares.
AGENT_PLUGINS_SCHEMA = "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"
AGENT_PLUGINS_FIELDS = {
    "$schema", "name", "version", "description", "author", "homepage",
    "repository", "license", "keywords", "extensions",
}

# Identity fields copied out of plugin.json, in the order every manifest
# writes them, so a regenerated file diffs cleanly.
SHARED = ["name", "version", "description", "author", "homepage",
          "repository", "license", "keywords"]

failures: list[str] = []
changed: list[str] = []


def fail(msg: str) -> None:
    # Several checks parse the same frontmatter, so the same complaint can
    # arrive twice. Report each one once.
    if msg not in failures:
        failures.append(msg)


def read_json(rel: str) -> dict:
    return json.loads((ROOT / rel).read_text())


def write_if_changed(rel: str, text: str, check: bool) -> None:
    path = ROOT / rel
    current = path.read_text() if path.exists() else None
    if current == text:
        return
    changed.append(rel)
    if check:
        fail(f"{rel} is out of date — run scripts/sync.py")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def dump_json(obj: dict) -> str:
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


def frontmatter(path: Path) -> tuple[dict, str, str]:
    """Return (parsed frontmatter, raw frontmatter, body)."""
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", path.read_text(), re.S)
    if not m:
        fail(f"{path.relative_to(ROOT)} has no YAML frontmatter")
        return {}, "", ""
    raw, body = m.group(1), m.group(2)
    try:
        import yaml
    except ImportError:
        fail("PyYAML is not installed: pip install pyyaml, or run "
             "`npx -y skills add . --list`, which parses strictly too")
        return {}, raw, body
    try:
        data = yaml.safe_load(raw)
    except Exception as exc:  # noqa: BLE001 - the message is the point
        fail(f"{path.relative_to(ROOT)}: frontmatter is not valid YAML — {exc}")
        return {}, raw, body
    return data or {}, raw, body


# ---------------------------------------------------------------- manifests

def sync_manifests(check: bool) -> dict:
    src = read_json("plugin.json")

    if src.get("$schema") != AGENT_PLUGINS_SCHEMA:
        fail(f"plugin.json $schema must be exactly {AGENT_PLUGINS_SCHEMA}")
    extra = set(src) - AGENT_PLUGINS_FIELDS
    if extra:
        fail("plugin.json has fields Agent Plugins 1.0.0 does not permit "
             f"(the schema is closed): {sorted(extra)}")
    if "skills" in src:
        fail("plugin.json must not declare `skills`: Agent Plugins finds them "
             "at the fixed location skills/<name>/SKILL.md")

    shared = {k: src[k] for k in SHARED if k in src}

    # Claude Code — the same field set, no $schema.
    write_if_changed(".claude-plugin/plugin.json", dump_json(dict(shared)), check)

    # Codex — the shared fields, then Codex's own `skills` and `interface`,
    # which this script preserves rather than generates.
    codex_existing = read_json(".codex-plugin/plugin.json")
    codex = dict(shared)
    codex["skills"] = codex_existing.get("skills", "./skills/")
    if "interface" in codex_existing:
        codex["interface"] = codex_existing["interface"]
    write_if_changed(".codex-plugin/plugin.json", dump_json(codex), check)

    # Cursor — documents author as {name, email}; no url, and no homepage,
    # repository, license or keywords beyond what it lists. displayName is
    # Cursor's own and is preserved.
    cursor_existing = read_json(".cursor-plugin/plugin.json")
    cursor = {"name": shared["name"]}
    if "displayName" in cursor_existing:
        cursor["displayName"] = cursor_existing["displayName"]
    cursor["version"] = shared["version"]
    cursor["description"] = shared["description"]
    cursor["author"] = {"name": shared["author"]["name"]}
    for k in ("homepage", "repository", "license", "keywords"):
        if k in shared:
            cursor[k] = shared[k]
    write_if_changed(".cursor-plugin/plugin.json", dump_json(cursor), check)

    # Gemini CLI — name and version are required and throw if absent;
    # description is documented and displayed. Nothing else is wanted:
    # contextFileName would make this always-on context in every session.
    write_if_changed("gemini-extension.json", dump_json({
        "name": shared["name"],
        "version": shared["version"],
        "description": shared["description"],
    }), check)

    # The marketplace entry repeats the description and carries its own version.
    mk = read_json(".claude-plugin/marketplace.json")
    mk["metadata"]["version"] = shared["version"]
    for entry in mk["plugins"]:
        if entry["name"] == shared["name"]:
            entry["description"] = shared["description"]
    write_if_changed(".claude-plugin/marketplace.json", dump_json(mk), check)

    return shared


def sync_skill_version(version: str, check: bool) -> None:
    rel = "skills/curb-sale/SKILL.md"
    path = ROOT / rel
    data, raw, _ = frontmatter(path)
    if not data:
        return
    if data.get("metadata", {}).get("version") == version:
        return
    text = path.read_text()
    new_raw = re.sub(r"(?m)^(  version:\s*).*$", rf"\g<1>{version}", raw)
    if new_raw == raw:
        fail(f"{rel}: could not find `  version:` under metadata to update")
        return
    write_if_changed(rel, text.replace(raw, new_raw, 1), check)


# ----------------------------------------------------------------- commands

def sync_commands(check: bool) -> None:
    for md in sorted((ROOT / "commands").glob("*.md")):
        data, _, body = frontmatter(md)
        if not data:
            continue
        description = data.get("description")
        if not description:
            fail(f"{md.name} has no description in its frontmatter")
            continue
        if md.stem != data.get("name"):
            fail(f"{md.name}: frontmatter name {data.get('name')!r} does not "
                 "match the filename")

        prompt = body.strip().replace("`$ARGUMENTS`", "{{args}}")
        prompt = prompt.replace("$ARGUMENTS", "{{args}}")

        if "'''" in prompt:
            fail(f"{md.name}: body contains ''' and cannot become a TOML "
                 "multi-line literal string")
            continue
        # Gemini executes !{...} as a shell command and inlines @{...} as a
        # file. Neither belongs in a prompt copied from markdown.
        for token in ("!{", "@{"):
            if token in prompt:
                fail(f"{md.name}: body contains {token} which Gemini would "
                     "interpret rather than print")

        # A TOML basic string ("...") processes backslash escapes; a literal
        # string ('''...''') does not. Descriptions carry quotes, apostrophes
        # and backslashes, so the two forms are not interchangeable, and
        # picking the wrong one yields a file that parses and says something
        # else. Do not reason about the escape rules: generate, parse back,
        # and compare.
        toml = (f"description = {json.dumps(description, ensure_ascii=False)}\n"
                f"\nprompt = '''\n{prompt}\n'''\n")

        try:
            import tomllib
        except ImportError:
            fail("Python 3.11+ is required to verify that generated TOML "
                 "round-trips; the escape rules are not safe to assume")
        else:
            try:
                back = tomllib.loads(toml)
            except Exception as exc:  # noqa: BLE001
                fail(f"generated commands/{md.stem}.toml is not valid TOML - {exc}")
                continue
            if back["description"] != description:
                fail(f"commands/{md.stem}.toml: the description does not survive "
                     "a TOML round-trip; an escape was mangled")
                continue
            if back["prompt"].strip() != prompt:
                fail(f"commands/{md.stem}.toml: the prompt does not survive a "
                     "TOML round-trip; an escape was mangled")
                continue

        write_if_changed(f"commands/{md.stem}.toml", toml, check)


# ------------------------------------------------------------------- checks

def check_descriptions() -> None:
    """A plain YAML scalar cannot contain ": ". A colon followed by a space
    opens a nested mapping and the whole file is rejected — by strict parsers
    only, which is why every runtime we can test interactively missed it."""
    targets = [ROOT / "skills/curb-sale/SKILL.md", *sorted((ROOT / "commands").glob("*.md"))]
    for path in targets:
        data, raw, _ = frontmatter(path)
        for line in raw.splitlines():
            m = re.match(r"^(\s*)(\w[\w-]*):\s(.*)$", line)
            if not m:
                continue
            value = m.group(3)
            if not value or value[0] in "\"'|>[{":
                continue  # quoted or block scalar: a colon is safe there
            if ": " in value:
                fail(f"{path.relative_to(ROOT)}: `{m.group(2)}` is an unquoted "
                     'YAML scalar containing ": " — use an em-dash. Strict '
                     "parsers reject the file whole and report no skills.")

    for rel in sorted(p.name for p in (ROOT / "commands").glob("*.toml")):
        try:
            import tomllib
        except ImportError:
            return
        try:
            tomllib.loads((ROOT / "commands" / rel).read_text())
        except Exception as exc:  # noqa: BLE001
            fail(f"commands/{rel} is not valid TOML — {exc}")


def check_snippet_size() -> None:
    """README quotes the paste block's size in prose. A number in prose is a
    copy, and copies drift."""
    size = len((ROOT / "agents-snippet.md").read_bytes())
    readme = (ROOT / "README.md").read_text()
    quoted = re.search(r"is ([\d,]+) characters", readme)
    if not quoted:
        fail("README.md no longer states the size of agents-snippet.md; either "
             "restore the sentence or drop this check")
        return
    stated = int(quoted.group(1).replace(",", ""))
    if stated != size:
        fail(f"README.md says agents-snippet.md is {stated:,} characters; it is "
             f"{size:,}. Update the sentence.")


def check_no_mcp() -> None:
    """This repo declares no MCP server, by choice.

    https://curb.sale/mcp is live. A runtime that installs this plugin already
    holds the contract in SKILL.md and makes the same calls over plain HTTP, so
    declaring the server would open a connection at every session start for
    tools the skill already describes. To add MCP later, delete this check
    first. Do not add a key while a check forbids it.
    """
    for path in ROOT.rglob("*.json"):
        if ".git" in path.parts:
            continue
        try:
            text = path.read_text()
        except UnicodeDecodeError:
            continue
        if "mcpServers" in text:
            fail(f"{path.relative_to(ROOT)} declares mcpServers. This repo "
                 "ships no MCP declaration; see check_no_mcp.")
    if (ROOT / "mcp.json").exists() or (ROOT / ".mcp.json").exists():
        fail("an mcp.json exists. This repo ships no MCP declaration; "
             "see check_no_mcp.")


def check_online() -> None:
    import urllib.request
    with urllib.request.urlopen(AGENT_PLUGINS_SCHEMA, timeout=20) as r:
        schema = json.load(r)
    live = set(schema["properties"])
    if live != AGENT_PLUGINS_FIELDS:
        fail("the published Agent Plugins schema no longer matches the field "
             f"list in this script: added {sorted(live - AGENT_PLUGINS_FIELDS)}, "
             f"removed {sorted(AGENT_PLUGINS_FIELDS - live)}")
    if schema.get("additionalProperties") is not False:
        fail("the Agent Plugins schema is no longer closed; re-read it before "
             "adding a field")


def main() -> int:
    check = "--check" in sys.argv
    shared = sync_manifests(check)
    if shared:
        sync_skill_version(shared["version"], check)
    sync_commands(check)
    check_descriptions()
    check_snippet_size()
    check_no_mcp()
    if "--online" in sys.argv:
        check_online()

    for msg in failures:
        print(f"FAIL  {msg}", file=sys.stderr)
    if failures:
        return 1
    if check:
        print("in sync")
    elif changed:
        for rel in changed:
            print(f"wrote {rel}")
    else:
        print("in sync; nothing to write")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
