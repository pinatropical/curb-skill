# Working on curb-skill

This repo *packages* curb.sale for agent runtimes. It is not the product. The
product is a live HTTP API at `https://curb.sale` that needs no account, no API
key and no signup, and that works for anyone who never installs a thing from
here. Nothing in this repo is required to use curb.sale.

If you landed here because someone asked you to **use** curb.sale rather than
change it, stop reading and fetch `https://curb.sale/index.md` — the whole API,
under 4,500 characters. `agents-snippet.md` in this directory is the same thing
compressed to a paragraph you can append to any instructions file.

## The server is the source of truth

`https://curb.sale/index.md` (short) and `https://curb.sale/docs.md` (long) are
the contract. Every file here ships on a different clock from the API, so where
a file here and the server disagree, **the file here is wrong**. Fix the file.

Before changing any copy that states a limit, a field name or an error code,
fetch the live page and check it:

```bash
curl -s https://curb.sale/index.md
curl -s https://curb.sale/docs.md
```

That rule does not settle the one case where two live pages contradict each
other, which happens because they deploy on different clocks. Right now
`/index.md` says a photo may be 20 MB while `/docs.md` and `/openapi.json` still
say 10 MB. When two pages disagree the enforcing code in the product repo wins,
and the stale page is a deploy to chase rather than a number to copy down.

## Never imply an account is needed

The primary path is unauthenticated and always will be. A person tells an agent
"sell this" and gets a live public URL back in seconds, from one POST. Nothing
in this repo, and nothing anyone installs from it, changes that.

An optional account surface is being built in the product repo: one
unauthenticated `POST /account` mints a `curb_k_` key that groups listings you
already control by `edit_token`. **It grants nothing** — no raised rate limit,
no skipped moderation, no capability. It is also **not deployed**; `POST
/account` and `GET /me` both answer `404 not_found` on curb.sale today, so no
file here may describe it as callable. Check before writing about it at all:

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://curb.sale/me
```

When it does answer 200, mention it only where a reader is already asking about
managing several listings, and never in a sentence that could be read as a
prerequisite. Description fields, marketplace blurbs and plugin manifests are
marketing surfaces where "no account, no API key, no signup" has to survive
being truncated.

## Facts that must survive every rewrite

- **At least one of `text` or `photo`.** Both is better. Text alone lists fine;
  a photo alone lists fine and the server writes the words.
- **Always send `location`.** Omitted, the server geolocates the caller's IP —
  which is the *agent's*, not the user's. From a datacenter it refuses with
  `400 location_required` rather than guessing. Ask the user for their city.
- **Prices are cents. Everywhere.** `300` is $3.00, on a listing and on
  `min_price` / `max_price` alike. `price_cents` is the unambiguous name; write
  that one. Never invent a price: with no amount anywhere it stays UNSTATED —
  null, never `0`. An unstated price and a free item are different listings.
- **`edit_token` and `claim_url` are returned once** and cannot be recovered —
  that is the server's own wording, and `manage_url` is once-only with them
  because it carries the `edit_token` in its fragment. All three get copied to
  the user byte for byte, never truncated.
- **The listing URL is live immediately**; search indexing lags ~10 minutes.
  Never tell the user to wait for the URL.
- **6 photos per listing, 20 MB each, 48 MB per request.** These are the
  enforced constants — `MAX_PHOTOS_PER_LISTING`, `MAX_PHOTO_BYTES` and
  `MAX_REQUEST_BYTES` in the product's `src/`. `/index.md` agrees; `/docs.md`
  and `/openapi.json` still say 10 MB and no `48 MB` at all, because they lag a
  deploy. Do not "correct" 20 down to 10.
- **Listings expire in 30 days** unless the listing is claimed — which is
  opening `claim_url`, giving an email, and typing back the code sent there.
  Opening the link on its own claims nothing.
- **Coordinates are fuzzed to ~100m before storage.** A listing is a home.
- **No payment, escrow, shipping or delivery.** Two people meet. Do not write
  copy that implies otherwise.
- Physical goods only. Buyers reach sellers through an accountless email relay,
  so phone numbers and email addresses never belong in listing text.

## Do not invent a packaging format

Every manifest, filename, config key and install command in this repo must be
verified against that runtime's own current documentation before it is written.
A file in a shape the runtime does not read is worse than no file: it looks
supported and silently does nothing.

Two rules follow from that.

**No orphan manifests.** A manifest is only worth shipping if a documented
install command reaches it. A plugin manifest that no marketplace or install
path points at does nothing at all, in any runtime.

**No claim for a surface that is not live.** Do not add MCP, OAuth, webhooks or
a hosted connector to any manifest, README or skill file until the endpoint
answers 200 in production.

**Re-check the absences too.** A statement that a surface does not exist goes
stale as fast as a statement that it does, and nothing returns 404 to prove it
wrong. Re-measure both before a release.

`POST https://curb.sale/mcp` answers 200. It is a Streamable HTTP MCP server
with eight tools. This repo declares no `mcpServers` key, and that is a choice:
a runtime that holds this skill already has the contract, and needs no
connection to use it.

If a format cannot be verified, say so and ship nothing for it.

## Layout

`skills/curb-sale/SKILL.md` is the one path every runtime in scope agrees on.
Keep it there and do not nest it deeper: Agent Plugins clients are required to
look at each immediate child of `skills/` and are forbidden from searching
deeper, so a skill one directory further down is invisible rather than broken.

`plugin.json` at the repo root is the portable Agent Plugins 1.0.0 manifest.
Its schema is closed — `additionalProperties: false`, and the only permitted
top-level fields are `$schema`, `name`, `version`, `description`, `author`,
`homepage`, `repository`, `license`, `keywords` and `extensions`. There is no
`skills` field; skills are found at the fixed location, not declared. Validate
against the published schema rather than against memory:

```bash
python3 -c 'import json,re,urllib.request
s=json.load(urllib.request.urlopen("https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"))
m=json.load(open("plugin.json"))
assert not set(m)-set(s["properties"]), set(m)-set(s["properties"])
assert m["$schema"]==s["properties"]["$schema"]["const"]
print("conforms")'
```

Every other manifest goes at exactly the path its own runtime documents, and
nowhere else. `AGENTS.md` is this file, `CLAUDE.md` imports it because Claude
Code reads `CLAUDE.md` and not `AGENTS.md`, and `agents-snippet.md` is the
paste-in block.

One known-unverified overlap, recorded rather than guessed at: Cursor documents
both formats — "An Agent Plugin has a `plugin.json` manifest at its root. A
Cursor Plugin has a `.cursor-plugin/plugin.json` manifest" — and this repo now
carries both. Cursor's preference between the two is not documented, and
`cursor.com/docs/plugins/reference` returns 404. Keep both manifests in
agreement on name, version and no-account, so that either choice works. This
repo is unverified on Cursor. Verify it there before you state Cursor support
in the README.

## Verifying a change

```bash
bash -n skills/curb-sale/scripts/curb.sh
skills/curb-sale/scripts/curb.sh sell --dry-run --text 'test' --location 'Austin, TX'
python3 -c 'import json,sys; [json.load(open(p)) for p in sys.argv[1:]]' \
  plugin.json .claude-plugin/plugin.json .claude-plugin/marketplace.json \
  .codex-plugin/plugin.json .cursor-plugin/plugin.json gemini-extension.json
```

### Parse the frontmatter strictly. This one is not optional

**Interactive runtimes parse YAML frontmatter leniently, so none of them detect
a malformed one.** Claude Code, Codex, Gemini CLI and Cursor all load a
`description:` that is invalid YAML. Strict parsers reject it, and report "No
skills found". Run the strict check before you publish. CI runs it on every
push.

Run both of these. They are two independent parsers and cost a few seconds:

```bash
npx -y skills add "$PWD" --list   # must print "Found 1 skill", not "No skills found"
npx -y @google/gemini-cli@latest extensions validate .   # "successfully validated"
python3 -c '
import yaml, re, glob, sys
bad = 0
for f in glob.glob("skills/**/SKILL.md", recursive=True) + glob.glob("commands/*.md"):
    fm = re.match(r"^---\n(.*?)\n---\n", open(f).read(), re.S)
    try:
        yaml.safe_load(fm.group(1))
    except Exception as e:
        bad += 1
        print("FAIL", f, e)
sys.exit(bad)'
```

The specific footgun: **a plain YAML scalar cannot contain `": "`.** A colon
followed by a space turns the rest of the line into a nested mapping and the
file is rejected whole. It is easy to write by accident in a description that
introduces its examples — `find one nearby: "used desk near Austin"` — and it is
invisible in four of the five runtimes. Use an em-dash. The same applies to
every description in `commands/*.toml`.

### Bump every manifest together

Five files and one frontmatter block carry a version, and **different runtimes
read different ones** — so a version bumped in one place and not the others shows
a different number depending on which runtime the user is in:

```
plugin.json  .claude-plugin/plugin.json  .codex-plugin/plugin.json
.cursor-plugin/plugin.json  gemini-extension.json
skills/curb-sale/SKILL.md   metadata.version
```

**Do not bump them by hand. Edit `plugin.json` and run `scripts/sync.py`.**
Every other manifest is derived from it, along with `commands/*.toml` from the
matching `commands/*.md` and the byte count README quotes for
`agents-snippet.md`. `scripts/sync.py --check` exits 1 on any drift and runs in
CI, so a hand-edited copy fails the build instead of shipping. Hand-maintenance
is what produced the drift this section exists to describe: four `commands/*.toml`
files silently gained three improvements their `.md` sources never got back,
inside one week.

Two things `sync.py` deliberately does not own, because a generator would
flatten them: the `interface` block in `.codex-plugin/plugin.json`, which is
Codex's own, and everything under `skills/curb-sale/**`, which is written by
hand and read by every runtime unchanged.

**Which one Codex reads changed between two patch releases, so do not trust the
order written here — re-measure it.** Same repo, same three manifests, versions
set to 9.9.9 (root) / 5.5.5 (`.codex-plugin`) / 1.1.1 (`.claude-plugin`):

| codex-cli | installs | authoritative manifest |
|---|---|---|
| 0.145.0 | `curb-sale/5.5.5` | `.codex-plugin/plugin.json` — root ignored entirely |
| 0.148.0 | `curb-sale/9.9.9` | root `plugin.json` |

On 0.148.0 the full order is root `plugin.json` → `.codex-plugin/plugin.json` →
`.claude-plugin/plugin.json`: delete the root and it returns 5.5.5, delete that
too and it returns 1.1.1. Three patch releases inverted which file is
authoritative.

Note which way this cuts. `DISCOVERABLE_PLUGIN_MANIFEST_PATHS` in `codex-rs`
lists `.codex-plugin` first while the agent-plugins overlay implies the root
manifest supplies name and version. On 0.145.0 the binary contradicted that and
the binary was right *about 0.145.0*; by 0.148.0 the shipped behaviour had moved
to what the source implied. Reading the source and running the old binary would
both have been wrong. Run it pinned to `@latest`, on a throwaway clone with an
isolated `CODEX_HOME`, so nothing touches the working tree or your real config:

```bash
git clone -q . /tmp/cro/curb-skill && cd /tmp/cro/curb-skill
python3 - <<'PY'
import json
for p, v in [("plugin.json", "9.9.9"),
             (".codex-plugin/plugin.json", "5.5.5"),
             (".claude-plugin/plugin.json", "1.1.1")]:
    m = json.load(open(p)); m["version"] = v
    json.dump(m, open(p, "w"), indent=2, ensure_ascii=False)
PY
export CODEX_HOME=/tmp/cro/home
mkdir -p "$CODEX_HOME"          # codex errors out if it does not exist
npx -y @openai/codex@latest plugin marketplace add "$PWD"
npx -y @openai/codex@latest plugin add curb-sale@curb-sale
# prints: Installed plugin root: /tmp/cro/home/plugins/cache/curb-sale/curb-sale/<version>
rm -rf /tmp/cro
```

A clone plus `CODEX_HOME` is what makes this safe to run at any time: there is
nothing to restore afterwards, so it cannot discard another agent's uncommitted
edits to the shared manifests the way an in-place edit and `git checkout --`
would.

Keeping all five in sync is what makes the whole question moot, which is the
actual defence — the read order only matters when they disagree.

### The skill description is capped, and the cap moves between releases

Codex renders the initial skill list at "at most 2% of the model's context
window, or 8,000 characters when the context window is unknown", and "shortens
skill descriptions first". That is a **cap**, not a fixed width: a description
shorter than it passes through whole, a longer one is cut to it.

**The number is version-dependent. Measure it, never quote it.** Across all 178
rendered entries on one machine:

| codex-cli | longest description that survived |
|---|---|
| 0.145.0 | ~52 characters |
| 0.148.0 | ~60 characters |

Three patch releases moved it by eight characters. Any fixed number written here
is wrong by the next release, so the rule is the shape of the sentence and not a
budget: **open with the verbs and the domain.** At either cap that yields
`Sell or give away something you own on curb.sale…`, which is matchable. The
earlier opening yielded `This skill should be used when the user asks to "s` —
no verb, no domain, nothing to match "sell my couch" against.

Measure across every entry, not just ours: ours alone cannot tell you whether a
short string was capped or merely short.

```bash
npx -y @openai/codex@latest debug prompt-input \
  | python3 -c '
import re, sys
d = re.findall(r"- [A-Za-z0-9_.:-]+: ((?:(?!\(file:).)*?)\s*\(file:", sys.stdin.read())
print("longest surviving:", max(len(x) for x in d), "chars, across", len(d), "entries")'
```

The paste text has exactly one home, `agents-snippet.md`. README links to it;
nothing copies it. A command printed twice is a command that will eventually
disagree with itself, and the copy nobody remembers to update is the one a
stranger pastes.

### `gemini` may not be on PATH even when it is installed

Under a node version manager the bare name hits a shim and fails in a way that
reads like "not installed":

```
nodenv: gemini: command not found
The `gemini' command exists in these Node versions: 22.11.0
```

It is installed. Put the real binary on PATH before verifying anything about
Gemini, or the next person concludes the runtime is unavailable and skips the
check:

```bash
export PATH="$HOME/.anyenv/envs/nodenv/versions/22.11.0/bin:$PATH"
gemini --version   # 0.16.0 on this machine — forty minor versions stale
```

**Check `gemini --version` against the published one before concluding that a
command does not exist.** The local install is 0.16.0; `npm dist-tags` for
`@google/gemini-cli` puts `latest` at 0.56.0. On 0.16.0 only `gemini mcp` and
`gemini extensions` are present, so `gemini skills install <url> --path <dir>`
fails with `Unknown argument: path` — the query parser eating an unknown flag,
not evidence that the command is wrong. On 0.56.0 `gemini skills` is real,
`--path` and `--consent` are real, and the install works verbatim against the
public repo:

```bash
npx -y @google/gemini-cli@latest skills install \
  https://github.com/curb-sale/curb-skill.git --path skills/curb-sale --consent
npx -y @google/gemini-cli@latest skills list --all   # curb-sale [Enabled]
npx -y @google/gemini-cli@latest skills uninstall curb-sale
```

That lands `SKILL.md`, `references/` and `scripts/` in `~/.gemini/skills/curb-sale`.
Pin `@latest` through `npx` for any Gemini check. A stale local binary produces a
false negative that reads exactly like a broken instruction, and the cost of
believing it is deleting a line that works for every current user.

**This is the general rule, not a Gemini one.** Measure the version your READER
will have, not the one this machine happens to hold. Every runtime here is
checked against a local binary that ages independently:

```bash
codex --version   && npm view @openai/codex version        # 0.145.0 vs 0.148.0
gemini --version  && npm view @google/gemini-cli version   # 0.16.0  vs 0.56.0
```

Three measurements in this file point in different directions, which is the
whole reason to state the rule as a version and not a verdict:

- `gemini skills` was declared fictional from a **0.16.0** binary and is real on
  **0.56.0**. The docs were right; the binary was stale.
- Codex's manifest read order on **0.145.0** contradicted its own main-branch
  source. The binary was right; the source described where it was going.
- That same read order **flipped on 0.148.0** to match the source after all.
  Three patch releases turned the previous bullet's verdict inside out.

So neither "trust the binary over the docs" nor "trust the docs over the binary"
is the lesson, and "measure it" is not sufficient on its own. A measurement
carries the version it was taken on, it expires, and this file dates every one so
you can tell when it has. Re-run any of them pinned to `@latest` before leaning
on it — the read-order recipe above clones to `/tmp` and isolates `CODEX_HOME`
precisely so it is cheap enough to re-run rather than trust.

Then check the claim, not the intention: install the thing in the runtime it
claims to support and confirm it loads. A green JSON parse proves nothing about
whether anything reads the file.
