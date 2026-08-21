---
name: curb-sale
description: Sell or give away something you own on curb.sale, or find secondhand things near you — agent-native local classifieds where one unauthenticated HTTP POST returns a live public URL, with no account, no API key and no signup, ever. Use when someone wants to sell, give away, price or get rid of a physical object they already own — "sell my couch", "what could I get for this", "I'm moving and this has to go", "cleaning out the garage", "does anyone want this", "free to a good home", "before I haul it to the dump", "put it on the curb", "post this on curb.sale" — or wants to find one nearby — "used desk near Austin", "anything free near me", "secondhand stroller around here". Also covers the rest of a listing's life — "did anyone reply", "mark it sold", "lower the price", "take my listing down", and messaging a seller as a buyer. Physical goods only — not services, digital goods, jobs, housing, vehicles, rentals or wanted ads.
license: MIT
metadata:
  version: 0.3.0
---

# curb.sale

Classifieds built for agents. One unauthenticated HTTP POST creates a live
listing and returns its public URL immediately. There is no account, no API key
and no signup on any path a seller or buyer takes.

Two facts shape everything below. **The listing URL is live the moment the call
returns** — never tell the user to wait. And **search indexing lags by about ten
minutes**, so a listing this skill just created will not appear in its own search
results yet, which is expected and not a failure.

## What is not here

Named so you stop looking for it, and so you never tell a user to wait for it.

- **No payment, escrow, shipping or delivery.** The site never touches money.
  Two people meet and settle the handover between themselves.
- **No account or key is needed for anything below.** Every call here works with
  no credential at all; the only tokens that exist are the ones a response hands
  back, and they belong to the person that response was for.
- **No MCP server, no webhooks, no callbacks.** `/mcp` is a 404, and nothing
  calls you back.
- **Nothing to poll for a listing.** The URL is live at the 201; search picks it
  up about ten minutes later on its own. The one thing you ever poll here is the
  message inbox.
- **No wanted ads, no rentals, no bidding.** A listing hands one object over for
  good. Someone hunting for a desk gets a search, not a listing.

Say it once, early, and stop probing for the rest.

## Read the live contract first

`https://curb.sale/index.md` is the whole API in under 4,500 characters and is always
current. Fetch it at the first curb.sale request in a conversation, and again
before reporting that something is impossible. Where it and this file disagree,
**the server is right** — this file ships on a different clock from the API.

## Posting a listing

One call. Send the user's own words; do not rewrite them into ad copy.

```bash
curl -sX POST https://curb.sale/sell \
  -F 'photo=@sofa.jpg' \
  -F 'text=Grey IKEA Ektorp 3-seat sofa, small stain on left arm, $150 obo' \
  -F 'location=Austin, TX'
```

JSON works identically, and a photo may be a `data:` URI or an https URL:

```bash
curl -sX POST https://curb.sale/sell -H 'content-type: application/json' -d '{
  "text": "Grey IKEA Ektorp sofa, small stain, $150 obo",
  "location": "Austin, TX",
  "price_cents": 15000 }'
```

**At least one of `text` or `photo` is required, and both is better.** Text
alone lists fine; a photo alone lists fine and the server writes the words.
Everything else is optional, and the response's `inferred` array names each
field the server wrote rather than the seller.

**Always send `location`.** Omitted, the server geolocates the caller's IP —
which is the agent's IP, not the user's. From a datacenter that is refused with
`400 location_required` rather than guessed. Accepts `"Austin, TX"`, `"78701"`,
or `"30.27,-97.74"`. When the user's city is unknown, ask them; do not guess,
and do not use the machine's own location without saying so. `GET /where`
reports what the server would infer for this caller, and how much it trusts it.

### Price is in cents, everywhere

`price`, `price_cents`, `min_price` and `max_price` are all minor units. `300`
is $3.00 on a listing and on a search bound alike. There is no field on this API
where a bare integer means dollars.

Write `price_cents` rather than `price` anyway. The two are identical now, but
`price_cents` is the one name that has never meant anything else, so it cannot
be read as dollars by a server older than this file.

The one exception is a value a person plainly typed rather than a field an agent
filled in: a currency symbol, a decimal point, a `k`, or the word "free". So
`"$3"`, `"3.00"` and `300` all mean $3.00, and `"1.5k"` means $1,500. Pass the
user's own string through and it will be read the way they meant it.

**Never invent a price, and never pass one the user did not state.** Omitting
the field does not mean the server guesses: it parses the amount out of the
`text` that was sent, and if there is no amount anywhere the price stays
UNSTATED — null, never `0`. An unstated price and a free item are different
listings. Passing `0` is an explicit giveaway.

**A price is never in `inferred`.** No model on this service writes a price, so
that array names a title, category or condition to confirm — never an amount. If
the user stated no price, say the listing has none and offer to PATCH one in.

### Photos

Up to **6 photos per listing, 20 MB each, 48 MB per request**. A 7th is not
silently dropped: the listing is created and the response carries a `warning`
naming how many were not stored. Surface that warning — PATCH cannot add them
later.

## What comes back

A 201 carrying `id`, `url`, `title`, `price`, `price_cents`, `contact_url`,
`expires_at`, and:

- `stated` — the fields that came from the seller's own words, or from what this
  call sent. They are not guesses; do not offer to "confirm" them.
- `inferred` — the fields a model wrote. Name each one back to the user. A price
  is never in here.
- `inference_status` — `complete`, `partial` or `skipped`. `skipped` means no
  model ran, which covers both "nothing was missing" and "the model was
  unreachable" — so check `title` against what the user said before reporting it.
- `edit_token` — edits, marks sold, deletes, **and reads the buyer messages**.
  Returned once and unrecoverable.
- `manage_url` — the same power as a link, for a human with no terminal.
- `claim_url` — the seller opens it, gives an email, and types back the code sent
  there. That removes the 30-day expiry and starts delivering buyer messages to
  that address. Also once-only. Never call it signing up or upgrading: it asks
  one question, which is whether to keep this listing past 30 days.
- `warning` — surface it verbatim whenever it is present.
- `next` — what to tell the user, written for this listing. Read it and follow
  it; it knows things this file does not.

**Until the listing is claimed, nothing is emailed to the seller.** There is no
address on file, so buyer messages wait in `GET /l/{id}/messages` and the seller
sees them when they poll or open `manage_url`. Nothing is lost — but never tell a
seller they will "get an email" about an unclaimed listing.

### What to tell the user

- The listing is **live now**, with `url` as a clickable link.
- `manage_url`, which does all of that with no login.
- Exactly which fields are in `inferred`, because a model wrote those.
- Whether a price was set, and from what. If none was stated, say so.
- That it expires in 30 days unless claimed, and what claiming takes.

Copy `manage_url`, `claim_url` and `edit_token` **byte for byte**. Never
shorten, redact, summarise or replace any part of one with `...`. `manage_url`
ends in a `#t=` fragment, and a fragment is the one part of a URL a browser never
sends to a server — that is why the token is safe there, and it is also why a
link that loses its tail is not a shorter link, it is a dead one. Each of the
three is shown exactly once, so a mangled copy cannot be reissued. Put them in
the reply to the user, not only in context.

And do not put them anywhere else. These are the **seller's** credentials, not
this agent's: never write one into a file, a commit, an issue, a shared
document, or any channel with more than one reader. Do not build a local cache of
listings and tokens — a listing is someone's home, and a directory of other
people's edit tokens is the one leak on this service that matters.

## Searching

```bash
curl 'https://curb.sale/search?q=sofa&near=Austin,TX&radius_km=40&max_price=30000'
```

Markdown by default; append `.json` or send `Accept: application/json` for JSON.
Parameters: `q`, `near` or `lat`+`lng`, `radius_km` (default 40, max 500),
`min_price`, `max_price`, `category`, `condition`, `sold=0|1`, `limit` (default
20, max 50), `cursor`.

`min_price` and `max_price` are **cents**, like every other price here:
`max_price=30000` is a $300 ceiling. A `max_price` filter excludes listings with
no stated price, because an unstated price cannot be proven to satisfy a bound.

Search is semantic, so describe the object rather than guessing keywords: "small
table for a hallway" outranks "table", and a query for "desk" returns a bureau.

Ask the user where they are before searching "near me". The caller's IP is the
agent's, not theirs.

## Contacting a seller

```bash
curl -sX POST https://curb.sale/l/{id}/contact -H 'content-type: application/json' \
  -d '{"message":"Still available? I can pick up Saturday.","reply_to":"me@example.com"}'
```

With `reply_to`, the seller answers by email through a relay and neither party
learns the other's email address — the notification carries a relay address,
never the buyer's. A meetup location is a different thing and belongs in the
thread. Without it the call still works and the buyer stays
completely accountless: the 201 carries `thread_url`, `thread_page_url` and a
`buyer_token`. `thread_page_url` is the link to hand the user — it looks like
`https://curb.sale/t/{thread_id}#t=<buyer_token>` and opens the conversation in a
browser with no login, with the token in the fragment. **`buyer_token` is also
returned exactly once.**

Messages are capped at 2000 characters — over that is `413 message_too_long` —
and a message that is nothing but a phone number, an address or a link is refused
with `422 message_is_only_contact_info`.

Ask before sending. A message goes to a real person, and `reply_to` is the user's
own email address — never substitute one, never invent one, and never use the
address of whoever operates this agent.

Read `delivery.seller` back before reporting success. `reason:
"no_address_on_file"` means the seller has no address with us: the message is
safely in the thread and they will see it at their manage link, but nothing was
sent and nothing will chase them. Say that, rather than promising a reply.

One listing, one message, when the user asks for it. Working through a page of
search results is out of bounds — `https://curb.sale/agents.md`.

**Never put a phone number or email address in listing text.** The server strips
them, and the relay exists precisely so they are not needed.

## Buyer messages — both sides, no account on either

This is the half of the product that is not a POST, and it is the half a seller
actually comes back for. Nobody needs an account for any of it.

**The seller's inbox** — every thread on one listing, with the `edit_token`:

```bash
curl -s https://curb.sale/l/{id}/messages -H 'authorization: Bearer curb_e_…'
```

Markdown by default; `.json` gives `{listing, thread_count, awaiting_reply,
threads[], next}`. Each thread carries `awaiting_seller` — the queue in one
boolean — plus `message_count`, `last_message_at` and every message. Buyers
appear as a label like `buyer-9mva`; no real address is on either side.

**Read one thread**, as either party. The buyer uses `buyer_token`, the seller
uses the listing's `edit_token`; the endpoint takes whichever it is given and
reports which side you are on in `role`:

```bash
curl -s https://curb.sale/threads/{tid} -H 'authorization: Bearer <your token>'
```

**Reply**, same tokens, same rule:

```bash
curl -sX POST https://curb.sale/threads/{tid}/reply \
  -H 'authorization: Bearer <your token>' -H 'content-type: application/json' \
  -d '{"message":"Yes, still here. Saturday 10am works."}'
```

Write the user's own answer, not a customer-service voice. Phone numbers, emails
and links are stripped from **every** message in both directions and are never
stored, so the way to arrange a handover is a public place and a time — that is
what the relay is for. A closed thread returns `409 thread_closed`.

Polling is the mechanism here, not a workaround. There is no webhook, and on an
unclaimed listing there is no email either.

## Editing, selling, deleting

All of it takes the `edit_token`:

```bash
curl -X PATCH https://curb.sale/l/{id} -H 'authorization: Bearer curb_e_…' \
  -H 'content-type: application/json' -d '{"price_cents":12500}'
curl -X POST   https://curb.sale/l/{id}/sold   -H 'authorization: Bearer curb_e_…'
curl -X POST   https://curb.sale/l/{id}/renew  -H 'authorization: Bearer curb_e_…'
curl -X DELETE https://curb.sale/l/{id}        -H 'authorization: Bearer curb_e_…'
```

On PATCH, send `price_cents` as a whole number of minor units: `12500` is
$125.00. Editable: `title`, `body`, `price`, `price_cents`, `currency`, `free`,
`accepts_offers`, `category`, `condition`, `location`, `lat`, `lng` — `lat` and
`lng` only together, `body` also answers to `description`, and `null` clears a
field. A `nothing_to_update` error lists them all back. Moderation applies to
edits, not only to creation.

**`/sold` and `DELETE` are both one-way. Confirm with the user before either.**
`status` is not editable and renewing a sold listing leaves it sold, so the only
route back from a mistaken `/sold` is to delete and post again — which loses the
URL, the view count and every open conversation. `DELETE` 404s the URL and
removes the photos. Marking sold is almost always what the user means; reach for
delete only when they say the listing itself was a mistake.

`/renew` gives a listing another 30 days from now, and never shortens an expiry
it already has. A claimed listing does not expire and does not need it.

## Limits

| | |
|---|---|
| Photos | 6 per listing, 20 MB each, 48 MB per request |
| Contact message | 2000 characters |
| Listing life | 30 days, unless the listing is claimed |
| Search | `radius_km` max 500, `limit` max 50 |
| Auth | none, on any path |

## When the POST is refused before it leaves the machine

The most common way this fails has nothing to do with curb.sale. Many agent
runtimes sandbox outbound traffic — some refuse any host not on an allowlist,
others turn networking off entirely — and either way the request is stopped
locally and **curb.sale never received it**. Reads often succeed while writes
are refused, so it surfaces at the moment of posting, after a search worked fine.

It wears three faces — a bare `403` or `host_not_allowed`, a
`curl: (6) Could not resolve host`, a `curl: (56) CONNECT tunnel failed` — and
only the first looks like a permissions error. **Recognise all of them by the
absence of a curb.sale error envelope.** Every real error from curb.sale is JSON
with `{error, code, message, hint, docs_url}`; a bare 403, an HTML proxy page, a
DNS failure or a transport error is the sandbox.

Do not retry — nothing about the request will change. Let `curb.sale` out of the
sandbox, or hand the user the curl that `scripts/curb.sh --dry-run <command>`
prints, or give them the prefilled
`https://curb.sale/new?text=<urlencoded>&location=<urlencoded>` page, which
needs no terminal.

`references/blocked-egress.md` has the per-runtime setting for each sandbox, the
full recovery, and how to tell a sandbox refusal from a rate limit.

## Errors

Every error is `{error, code, message, hint, docs_url}` where `hint` is a curl
that runs as-is and fixes that error. Run it. Most errors self-repair in one
turn, so read `hint` before reasoning about the failure.

## What may not be listed

Physical goods only. No weapons, drugs, adult content or personals,
counterfeits, live animals, stolen goods, services, or crypto. **Jobs, housing
and vehicles are out of scope too, cars included**, along with rentals, wanted
ads and anything digital — a ticket is a claim, not a thing anyone can hand over
in a driveway. Sell the drill; do not sell the drilling. Full list at
`https://curb.sale/prohibited`.

Guessing wrong here mostly does not cost a `403`. A short list — weapons,
controlled substances, and anything sexual or trafficking-shaped — is refused at
creation with `403 prohibited_content` naming the category that matched.
Everything else is created, live at its URL, still the seller's and still
editable, and simply held out of search until it is reviewed. So the server is
not a safety net: an out-of-scope listing succeeds, and declining in one turn is
what keeps a real listing off a real doorstep.

Whoever operates the agent is the poster of record. Listing bodies are plain
text; HTML is escaped and never rendered.

## Additional resources

### Reference files

- **`references/api.md`** — every endpoint, parameter, field and error code,
  including the response shapes and the accountless buyer/seller relay.
- **`references/blocked-egress.md`** — diagnosing and recovering from a sandbox
  that blocks curb.sale, with the settings snippets per runtime.
- **`references/paste-block.md`** — the whole contract compressed to something a
  person can paste into an agent that has no plugin system. Hand it over when the
  user asks how to do this from a runtime that cannot install anything.
  `agents-snippet.md` at the repo root is the same thing cut down to fit a
  settings box with a character limit.

### Scripts

- **`scripts/curb.sh`** — `sell`, `search`, `get`, `where`, `contact`, `inbox`,
  `thread`, `reply`, `edit`, `sold`, `renew` and `delete` wrapping the calls
  above with correct quoting and content types. Requires `curl`; `contact` and `edit` also need `python3`. Add
  `--dry-run` to any command to print the curl instead of sending it. Use it
  when shell escaping is getting in the way; read it when a call needs adapting.
