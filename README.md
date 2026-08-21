# curb.sale for agents

**You do not need this repo.** curb.sale is a live HTTP API with no account, no
API key and no signup on any path. One unauthenticated POST creates a public
listing and returns its URL, from anything that can make an HTTP request:

```bash
curl -sX POST https://curb.sale/sell \
  -F 'photo=@sofa.jpg' \
  -F 'text=Grey IKEA Ektorp 3-seat sofa, small stain on left arm, $150 obo' \
  -F 'location=Austin, TX'
```

That is the whole product. [`https://curb.sale/index.md`](https://curb.sale/index.md)
holds the full contract in less than 4,500 characters. An agent can fetch that
page in the middle of a conversation and complete the task with no second
request.

This repo is a convenience, not a dependency. It packages the contract as a
skill. The agent then knows these rules before the first call, not after a
failed one:

- Prices are in cents.
- A listing needs a city. Your IP address belongs to the agent, not to you.
- `edit_token` is returned one time only. Save it.
- A sandbox can block the request. This is the most common cause of a failed
  first call, and the skill knows how to recover.

If you remove this repo, everything above still works. You lose only the head
start.

## Install

| Runtime | Command | What lands |
|---|---|---|
| **Claude Code** | `/plugin marketplace add curb-sale/curb-skill`<br>`/plugin install curb-sale@curb-sale` | skill + `/curb-sell` `/curb-search` `/curb-contact` `/curb-manage` |
| **Codex** | `codex plugin marketplace add curb-sale/curb-skill`<br>`codex plugin add curb-sale@curb-sale` | skill. [Turn its network on first](#codex) — the default failure looks like DNS, not a firewall |
| **Gemini CLI** | `gemini extensions install https://github.com/curb-sale/curb-skill` | skill + the same four commands, as `.toml` |
| **Cursor** | `git clone https://github.com/curb-sale/curb-skill ~/.cursor/plugins/local/curb-sale` | skill, then **Developer: Reload Window** |
| **VS Code / Copilot** | `cp -R skills/curb-sale ~/.agents/skills/` | skill. No manifest, no command |
| **Amp** | `amp skill add curb-sale/curb-skill` | skill |
| **~78 others**<br><sub>Zed, Cline, Roo, Warp, OpenCode, Windsurf, Kiro…</sub> | `npx skills add curb-sale/curb-skill` | skill, into whichever agents it finds installed |
| **Only the domain**<br><sub>no repo, no org, nothing but the URL</sub> | `npx skills add https://curb.sale` | skill. The site serves `/.well-known/agent-skills/index.json`, so this needs nothing from GitHub |
| **No plugin system**<br><sub>ChatGPT, the Claude and Gemini apps, any chat box</sub> | paste [`agents-snippet.md`](agents-snippet.md) into custom instructions | the contract, as text |

Then just say what you want:

> sell my old dresser, $80, I'm in Austin

> find me a used desk near Austin under $150

Every row above reads the same `skills/curb-sale/` directory.

If your runtime is not in the table, copy that folder into its skills directory.
That is the full install. Use `.agents/skills/`, which more runtimes accept than
any other path. Many runtimes also read `.claude/skills/`, so a global Claude
Code install is often already visible to them.

## Runtime notes

### Codex

Codex reads `.claude-plugin/marketplace.json` as a legacy-compatible marketplace.
It takes the name and version from one of the plugin manifests. All five
manifests come from one source and hold the same values, so the choice does not
change the result.

To confirm the install, run `codex debug prompt-input`. The skill shows in the
model-visible list with its path. This makes no API call.

Codex also reads a skill directory with no plugin. `$HOME/.agents/skills` is the
user location. `$REPO_ROOT/.agents/skills` is the project location.

```bash
mkdir -p ~/.agents/skills && cp -R skills/curb-sale ~/.agents/skills/
```

**Codex keeps networking off by default.** The `workspace-write` sandbox blocks
outbound traffic until you enable it. The first POST then fails with a DNS
error, not an HTTP status:

```
curl: (6) Could not resolve host: curb.sale
```

To enable networking, edit `~/.codex/config.toml`:

```toml
[sandbox_workspace_write]
network_access = true
```

To allow curb.sale only, enable the egress proxy and add one rule:

```toml
[features]
network_proxy = true

[permissions.curb]
extends = ":workspace"

[permissions.curb.network]
enabled = true

[permissions.curb.network.domains]
"curb.sale" = "allow"
```

You must use both parts. The proxy applies rules but grants no access on its own.

Three more errors are possible, and none of them come from curb.sale:

| Error | Cause | Action |
|---|---|---|
| `curl: (6) Could not resolve host` | Networking is off | Set `network_access = true` |
| `curl: (56) CONNECT tunnel failed, response 403` | The local proxy blocks the host | Add the host to `domains` |
| `curl: (7) Failed to connect to 127.0.0.1 port NNNNN` | The proxy is still starting | Send the request again |

The skill knows all three, and acts on them without your help.

### Gemini CLI

`gemini-extension.json` at the repo root is what makes this an extension. It
carries the skill plus a `.toml` copy of each command, which is the only command
format Gemini reads: `/curb-sell`, `/curb-search`, `/curb-contact` and
`/curb-manage`. If a command name is already in use, Gemini adds the extension name as a prefix:
`/curb-sale.curb-sell`.

Run the install from a shell. It does not work in interactive mode. Restart the
CLI when the install completes.

For the skill on its own, without the commands:

```bash
gemini skills install https://github.com/curb-sale/curb-skill.git \
  --path skills/curb-sale --consent
```

That subcommand is available after version 0.16.0. Run `gemini --version` first.

Copying the folder works on all versions and needs no CLI. Gemini reads
`~/.gemini/skills/` and `~/.agents/skills/` for a user, and `.gemini/skills/`
and `.agents/skills/` for a workspace. In each pair, `.agents` wins.

### Cursor

Cursor loads two plugin formats and this repo carries a manifest for each: the
portable `plugin.json` at the root, and `.cursor-plugin/plugin.json` in Cursor's
own format. Either loads from `~/.cursor/plugins/local`, which needs no review
and no paid plan. Symlink instead of cloning if you want to iterate:

```bash
ln -s "$PWD" ~/.cursor/plugins/local/curb-sale
```

The skill shows in **Customize → Skills**, under *Agent Decides*. Cursor puts a
skill there when the agent can select it without a command. This repo keeps that
behaviour. The `disable-model-invocation` flag would turn the skill into a typed
`/name`, and then only a user who already knows about curb.sale could reach it.

Cursor's choice between the two manifests is not documented, and this repo is
unverified on Cursor. Both manifests hold the same name, version and
no-account values, so the skill loads either way. The four commands load only if
Cursor reads its own manifest. Treat the commands as unconfirmed on Cursor.

For the skill alone: `cp -R skills/curb-sale ~/.cursor/skills/`. Cursor also
loads `~/.claude/skills/` and `.claude/skills/` for compatibility.

### Runtimes with no plugin system

[`agents-snippet.md`](agents-snippet.md) holds the contract in a few lines. It
is a bare markdown section. It has no title, no frontmatter and no wrapper, so
you can append it to any instructions file:

```bash
curl -sL https://raw.githubusercontent.com/curb-sale/curb-skill/main/agents-snippet.md >> AGENTS.md
```

Where to point that `>>`, checked against each runtime's own current docs:

| Runtime | Personal, all projects | Per project |
|---|---|---|
| Codex | `~/.codex/AGENTS.md` | `AGENTS.md`, git root down to cwd |
| Amp | `~/.config/AGENTS.md` or `~/.config/amp/AGENTS.md` | `AGENTS.md`, cwd and parents |
| Zed | `~/.config/zed/AGENTS.md` (`%APPDATA%\Zed\AGENTS.md` on Windows) | `AGENTS.md` |
| opencode | `~/.config/opencode/AGENTS.md` | `AGENTS.md`, cwd and parents |
| Claude Code | `~/.claude/CLAUDE.md`. It reads `CLAUDE.md`, not `AGENTS.md` | `CLAUDE.md` |
| Cursor | Settings → Rules, as a User Rule | `AGENTS.md`, root or any subdirectory |
| VS Code / Copilot | `~/.copilot/instructions/curb-sale.instructions.md`. This is a **folder** of `*.instructions.md` files, not a file to append to | `AGENTS.md` at the workspace root |
| Windsurf / Devin | `~/.codeium/windsurf/memories/global_rules.md` (6,000 char cap) | `AGENTS.md`, any workspace directory |
| Warp | Global Rules, in settings | `AGENTS.md`. The name must be in caps. A `WARP.md` beside it wins |
| Gemini CLI | `~/.gemini/GEMINI.md` | `GEMINI.md`, or `AGENTS.md` once `context.fileName` lists it |

Two runtimes merge nothing. opencode and Zed read the **first** file they match:

- opencode does not read `~/.claude/CLAUDE.md` if its own global file exists.
- Zed reads `AGENT.md` before `AGENTS.md`.

The snippet is 1,379 characters. You can paste it by hand into a settings box.
It fits every global-rules limit in the table above. The smallest is Windsurf's
6,000 characters.

For a longer version that also covers buyer messages and the seller's reply
path, use
[`skills/curb-sale/references/paste-block.md`](skills/curb-sale/references/paste-block.md).

## Allow the host

Agent runtimes sandbox outbound traffic. The first POST can fail before it
leaves your machine. curb.sale does not receive that request and cannot answer
it.

There are two kinds of failure:

- The runtime blocks a host that is not on an allowlist. You get
  `403 host_not_allowed`.
- The runtime turns networking off. You get a DNS failure and no HTTP status.

Codex is the second kind. See [Codex](#codex) above.

In `~/.claude/settings.json`:

```json
{
  "sandbox": {
    "network": {
      "allowedDomains": ["curb.sale"]
    }
  }
}
```

If you cannot change these settings, the skill still completes the task. It
gives you a curl command to run yourself, or a prefilled
`https://curb.sale/new?...` page that needs no terminal. For more, see
[`references/blocked-egress.md`](skills/curb-sale/references/blocked-egress.md).

## What is in here

```
skills/curb-sale/              every runtime above reads this one directory
  SKILL.md                     the contract: sell, search, contact, inbox, edit
  references/api.md            every endpoint, field, and error code
  references/blocked-egress.md recovering when the sandbox blocks the request
  references/paste-block.md    the whole loop, for a runtime with no skill system
  scripts/curb.sh              the calls with the quoting already right

commands/curb-sell.md          /curb-sell   (written once, as markdown)
commands/curb-search.md        /curb-search
commands/curb-contact.md       /curb-contact
commands/curb-manage.md        /curb-manage
commands/*.toml                the same four, generated for Gemini CLI, which
                               reads no other command format

plugin.json                    Agent Plugins 1.0.0: Cursor, VS Code, Copilot,
                               ChatGPT & Codex, Kiro, Hermes and three more
.claude-plugin/plugin.json     Claude Code
.claude-plugin/marketplace.json  the curb-sale marketplace; also what
                               `codex plugin marketplace add` resolves
.codex-plugin/plugin.json      Codex's own format, plus its install-surface copy
.cursor-plugin/plugin.json     Cursor's own format
gemini-extension.json          Gemini CLI

agents-snippet.md              the paste-in block, for runtimes with none of the above
AGENTS.md                      how to change this repo
CLAUDE.md                      one line, importing AGENTS.md, because Claude Code
                               reads CLAUDE.md and not AGENTS.md
scripts/sync.py                regenerates every derived file; --check fails on drift
```

`curb.sh` needs `curl`. The `contact` and `edit` subcommands also need `python3`
to build their JSON.

Every subcommand accepts `--dry-run`. This prints the curl command and sends
nothing.

## How the copies stay the same

Five manifests hold the same name, version and description. Four command prompts
exist twice, because Gemini CLI reads `.toml` and no other runtime does.

These files are generated. `plugin.json` and `commands/*.md` are the sources.
Every other manifest and every `.toml` is derived from them.

```bash
scripts/sync.py            # write every derived file
scripts/sync.py --check    # exit 1 if a derived file differs
```

`sync.py` also rejects a description that contains `": "`. In an unquoted YAML
scalar, a colon and a space start a nested mapping and make the file invalid.
Claude Code, Codex, Gemini CLI and Cursor accept the file anyway. Strict parsers
reject it, and the skill then does not load at all.

CI runs `--check` and a strict parser on every push.

## What this repo does not ship

- **No `mcpServers` key in any manifest.** The MCP server is live at
  `POST https://curb.sale/mcp`. It uses Streamable HTTP. It needs no
  authentication, no OAuth and no session. This plugin does not declare it. A runtime that
  installs this plugin already holds the contract in `SKILL.md`, and makes the
  same calls over plain HTTP. To use the MCP server, point your runtime at the
  URL:

  ```bash
  claude mcp add --transport http curb https://curb.sale/mcp
  ```

- **No Continue.dev file.** Continue publishes no skills format that could be
  verified from its documentation. Cursor has since acquired Continue, so use
  the Cursor manifest in this repo.
- **No Aider file.** Aider has no skill or plugin system. Its extension point is
  a read-only `CONVENTIONS.md`, which it reads through a project `AGENTS.md`.
- **No second marketplace manifest** for Codex or Cursor. `codex plugin
  marketplace add` resolves `.claude-plugin/marketplace.json`. Cursor documents
  its marketplace format for repositories that hold more than one plugin, where
  each `source` is a subdirectory. This repo holds one plugin at the root.

Every manifest, filename and config key in this repo is verified against that
runtime's current documentation before it is written. A file in a shape the
runtime does not read is worse than no file. It looks supported, and it does
nothing.

More: [`/docs.md`](https://curb.sale/docs.md) ·
[`/llms.txt`](https://curb.sale/llms.txt) ·
[`/openapi.json`](https://curb.sale/openapi.json) ·
[`/agents.md`](https://curb.sale/agents.md) ·
[`/prohibited`](https://curb.sale/prohibited)

## License

MIT. See [LICENSE](LICENSE).
