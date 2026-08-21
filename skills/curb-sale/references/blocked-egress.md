# When the request never leaves the machine

The most common way posting to curb.sale fails is not a curb.sale failure. Many
agent runtimes route outbound traffic through a proxy that refuses any host not
on an allowlist. The request is rejected locally, so **curb.sale never sees it
and cannot answer it**.

This matters because the usual recovery — read the error envelope, run the
`hint` — does not apply. There is no envelope. Nothing on the server can help,
because nothing on the server ran.

## Recognising it

| Signal | Meaning |
|---|---|
| `x-deny-reason: host_not_allowed` | Local egress proxy refused the host. |
| `X-Proxy-Error` on a 403 | Same, in Claude Code's sandbox. |
| 403 whose body is HTML or plain text | Not curb.sale. Every curb.sale error is JSON. |
| `curl: (6) Could not resolve host: curb.sale` | Codex's sandbox with network off. DNS never resolves. |
| `curl: (56) CONNECT tunnel failed, response 403` | Codex's egress proxy denied the host. The 403 is local. |
| Connection refused / DNS failure to `curb.sale` | Blocked or unroutable locally. |
| GETs succeed but POSTs fail | The classic shape — see below. |

The decisive test: **every real error from curb.sale is JSON containing
`{error, code, message, hint, docs_url}`.** Anything else — a bare 403, an HTML
proxy page, a transport error — came from the sandbox.

Two of those shapes are easy to misread and worth naming, because neither looks
like an allowlist problem at a glance. A **DNS failure** is what a default-deny
sandbox looks like from inside: the name never resolves, so there is no
connection to refuse and no status code to read. And a **403 from `CONNECT`** is
an egress proxy refusing to open the tunnel — the number is identical to an HTTP
403, but it arrives with no response body and curb.sale never saw the request.

A rate limit looks different: it is `429`, it is JSON, and it carries
`retry_after` plus a proof-of-work challenge. A 429 is worth retrying. A
`host_not_allowed` never is.

### Why reads work and writes do not

Runtimes often give the fetch or browse tool broad network access while the
code-execution sandbox is default-deny. A listing can therefore be read, parsed
and summarised, and then the contact or sell POST refused — from the same agent,
seconds apart. That asymmetry reads like a curb.sale permissions error and is
not one.

## Recovery

### 1. Allowlist the host

Claude Code and Cowork read `sandbox.network.allowedDomains`. In
`~/.claude/settings.json`:

```json
{
  "sandbox": {
    "network": {
      "allowedDomains": ["curb.sale"]
    }
  }
}
```

Project scope is `.claude/settings.json` in the repo, or
`.claude/allowed-hosts.json`. Managed environments may enforce
`managed-settings.json`, in which case the change belongs to an administrator
and the fallbacks below are the answer.

**Codex** turns network access off by default rather than filtering hosts. Its
own documentation is explicit: "the default `workspace-write` sandbox mode keeps
network access turned off unless you enable it in your configuration." So the
first symptom is not a refused host, it is a name that will not resolve. In
`~/.codex/config.toml`:

```toml
[sandbox_workspace_write]
network_access = true
```

To grant that access to curb.sale alone rather than to everything, add the
egress proxy and a single allow rule. Domain rules are allowlist-first, and
`deny` always beats `allow`:

The profile has to be SELECTED, not merely defined. Without
`default_permissions`, codex refuses to load the config file at all — not the
profile, the file — so every other setting in it silently stops applying. Telling
somebody to paste this without that line breaks their setup while explaining how
to reach us.

Measured on codex-cli 0.145.0: `codex doctor` reports
`✗ config  config could not be loaded` for the block below without the first
line, and `✓ config  loaded` with it. The leading colon in `":workspace"` is
required too, and fails the same way without it.

```toml
default_permissions = "curb"

[features]
network_proxy = true

[permissions.curb]
extends = ":workspace"

[permissions.curb.network]
enabled = true

[permissions.curb.network.domains]
"curb.sale" = "allow"
```

`features.network_proxy` only enforces the rules; it does not grant access on
its own. Network off plus proxy on is still network off. With the proxy on, any
host that is *not* allowed fails as `curl: (56) CONNECT tunnel failed, response
403` — that 403 is the proxy, not curb.sale.

**The first request after enabling the proxy can fail while the proxy starts.**
It comes back as a transport error with no status code, which is exactly the
shape this page teaches you to read as "the sandbox blocked it" — and here it
means the opposite, because the configuration is right and the second attempt
succeeds. Measured on 0.148.0, four consecutive runs of one allowed request:
`000, 200, 200, 200`. So this is the single case where retrying once is correct.
If a second attempt also fails, it is a real block and the rest of this page
applies.

All four behaviours above were re-measured on codex-cli **0.148.0** and hold.
Note that `network_access` lives under `[sandbox_workspace_write]` and applies
only when that mode is active: checking it with `codex sandbox`, which defaults
to something stricter, shows a DNS failure that looks like the setting being
ignored. Add `-c sandbox_mode="workspace-write"` when testing it by hand.

Other runtimes name this differently — "network egress settings", "allowed
hosts", "outbound domains" — but the shape is the same: let `curb.sale` out.

### 2. Hand the curl to the user

The user's own shell has no such restriction. Give them the complete command,
already filled in, and tell them what it returns.

`scripts/curb.sh --dry-run` exists for exactly this. It prints the command it
would have sent and sends nothing, with the quoting already correct — which
matters, because the listing text is free prose that will contain an apostrophe
or a newline the moment it is a real listing:

```bash
scripts/curb.sh --dry-run sell \
  --text "Grey IKEA Ektorp sofa, small stain, \$150 obo" \
  --photo sofa.jpg --location "Austin, TX"
```

```bash
curl -sS -X POST https://curb.sale/sell -F 'text=Grey IKEA Ektorp sofa, small stain, $150 obo' -F photo=@sofa.jpg -F 'location=Austin, TX'
```

Hand over the second line. Say that the response contains an `edit_token` shown
only once, so they should paste the whole response back rather than just the
URL.

### 3. Hand over a prefilled page

For a user without a terminal, or with a photo the agent cannot upload:

```
https://curb.sale/new?text=<urlencoded>&location=<urlencoded>
```

The page opens with those fields populated. They attach the photo and press one
button. Do not put anything private in the query string — it is a URL, and it
lands in history and logs. Listing text is public by definition; an email
address is not, so never prefill `contact_email` this way.

## What not to do

- **Do not retry.** Nothing about the request changes between attempts.
- **Do not fall back to another host or a proxy.** Routing an unauthenticated
  write through a third party puts a listing, and the once-only `edit_token` in
  its response, in someone else's hands.
- **Do not tell the user curb.sale is down.** It is not, and they can verify
  that in a browser in five seconds, which makes every other thing the agent
  said less credible.
- **Do not silently drop the task.** The user asked to sell something. Report
  the block and offer a route above.

## Saying it well

A good handoff names the cause, kills the retry, and gives one action:

> I can read curb.sale but my sandbox blocks outbound POSTs to it, so the
> listing was not created — the request never left this machine. Either run this
> yourself, or add `curb.sale` to `sandbox.network.allowedDomains` in
> `~/.claude/settings.json` and I will retry. The response includes an edit
> token shown only once, so paste the whole thing back.
