# curb.sale API reference

Every endpoint is callable right now with no account, no API key and no signup.
The live contract is `https://curb.sale/index.md` (short) and
`https://curb.sale/docs.md` (long). Where this file and the server disagree, the
server is right.

## Representations

Every GET is content-negotiated, and **markdown is the default**. HTML is served
only when a browser is proven. Precedence:

1. Path suffix — `/index.md`, `/search.json`, `/l/{id}.md`. URL identity; beats everything.
2. Query — `?format=md|json|html`, `?agent=1`, `?html=1`.
3. `Accept: text/markdown`, then `Accept: application/json`.
4. `Sec-Fetch-Dest: document` → HTML.
5. A short crawler and link-unfurler allowlist → HTML.
6. Otherwise markdown.

`GET /_probe` echoes the received headers and the negotiation verdict with the
reason. It is the fastest way to find out why a response was not what was
expected.

Every response carries `Link` (the discovery surface), `x-curb-sell` (the whole
write contract on one line, surviving a HEAD or a truncated body), and
`access-control-allow-origin: *` with OPTIONS preflight, so browser-sandboxed
agents can call the API cross-origin. Responses `Vary` on
`Sec-Fetch-Dest, Accept`, never on User-Agent.

## Money: one rule

**Every explicit price field on this API is in minor units.** `price`,
`price_cents`, `min_price` and `max_price` all read a bare integer as cents, so
`300` is $3.00 in all four. There is no field here where an integer means
dollars.

The escape hatch is that anything which is *not* a bare integer is read as
money a person typed: a decimal point, a currency symbol, a `k`, or the word
"free". `300`, `"3.00"` and `"$3"` are all $3.00; `"1.5k"` is $1,500; `"free"`
is `0`. An agent filling in a field writes the former, a person typing a budget
writes the latter, and neither has to know what the other would have done.

This is a change. `price_cents` used to be minor units while a numeric `price`
and both search bounds were major units — three conventions on one domain. If a
listing comes back priced a hundredfold off what was intended, that is the
symptom, and `price_cents` is the field name that has meant cents on every
version of the server.

A missing price stays missing. The server never writes `0` for an unknown price,
because a listing that says free when it is not is a lie. `0` means giveaway.

A stated `currency` does not re-denominate an amount parsed from text: `$150` is
15000 minor units of USD and does not become ¥15,000 by relabelling.

## POST /sell

Aliases with an identical handler: `POST /`, `/list`, `/listings`, `/post`,
`/api/listings`, `/api/v1/listings`.

Never send an `Authorization` header. A malformed or unknown credential is a
401, not a silent downgrade to anonymous.

### Accepted bodies

| Content-Type | Shape |
|---|---|
| `multipart/form-data` | `photo` file part(s) plus text fields. Best for a local file. |
| `application/json` | Fields below; `photo` may be a string or array of strings. |
| `image/jpeg`, `image/png`, `image/webp`, `image/heic` | Raw bytes as the entire body, zero fields. |
| `text/plain` | The whole body is `text`. |
| `application/x-www-form-urlencoded` | Same fields as JSON. |

### Fields

- `text` — free text. **At least one of `text` or `photo` is required, and both
  is better.** Text alone lists; a photo alone lists and the server writes the
  words from it.
- `photo` — `data:` URI, https URL, multipart file part, or an array. **6 per
  listing, 20 MB each, 48 MB per request.** A 7th does not fail the call: the
  listing is created and a `warning` names how many were not stored.
- `location` — `"Austin, TX"` | `"78701"` | `"30.27,-97.74"`. Optional but
  effectively required from a datacenter; see below.
- `price` / `price_cents` — the same thing: integer minor units. `15000` is
  $150.00. Prefer `price_cents`, whose name has never meant anything else.
- `title`, `description`, `category`, `condition`, `currency` — optional.
  Anything sent is used verbatim; anything omitted may be inferred.
- `contact_email` — accepted, and deliberately **not stored and never mailed**.
  Nobody has proved they can read that mailbox — anyone can post a listing naming
  a stranger — so the 201 names the address back as the one to type into the
  claim page and says plainly that nothing was kept. An address becomes durable
  only when a code sent to it comes back. Do not present it to the user as
  "we'll email you there".
- `condition` — one of `new`, `like_new`, `good`, `fair`, `for_parts`.

Send `idempotency-key` as a header on create if retrying automatically. It is
scoped with a caller fingerprint, so pair it with `poster_key`; sent alone, the
response carries a `warning` saying the key was ignored. Separately, an
identical listing posted twice within 24 hours returns the original with a 200
rather than creating a second one, so a plain retry is already safe.

### Price is never inferred

No model on this service writes a price. The `inferred` array can name `title`,
`description`, `category`, `condition`, `photo_alt` or `location` — never
`price`. The price comes from an explicit field or is parsed out of the `text`
that was sent; with no amount anywhere it stays null.

That is why "confirm the inferred fields" and "confirm the price" are two
separate things to tell the user.

### Response 201

`url`, `id`, `title`, `description`, `price`, `price_cents`, `currency`,
`is_free`, `accepts_offers`, `category`, `condition`, `location`,
`location_source`, `location_precision`, `location_guessed`, `city`, `region`,
`country`, `lat`, `lng`, `photo`, `photos[]`, `status`, `searchable`,
`searchable_at`, `created_at`, `expires_at`, `contact_url`, `edit_token`,
`manage_url`, `claim_url`, `stated[]`, `inferred[]`, `inference_status`,
`warning`, `next`, `edit_example`. Two more appear only when they apply:
`ignored_fields[]` and `notes[]`.

`stated` names the fields the caller or the seller's own words supplied;
`inferred` names the fields a model wrote. They are disjoint, and a price is
never in `inferred`. `inference_status` is `complete`, `partial` or `skipped`;
`skipped` means no model ran, which covers both "nothing was missing" and "the
model was unreachable", so check the title against the raw text rather than
assuming which.

`edit_token` and `claim_url` are returned **exactly once and cannot be
recovered**. Persist them or hand them to the user, byte for byte, before doing
anything else.

The listing is live at `url` the instant the 201 arrives. Search entry lags
about ten minutes; `searchable` flips after an index sweep. Never wait or poll
for it — it is not a failure state.

## Location and the datacenter problem

Precedence: explicit `lat`/`lng`, then `location` resolved against the
gazetteer, then the caller's IP.

The requesting IP belongs to the **agent**, not the user. A locally-run agent
geolocates to the user; a server-side agent geolocates to a datacenter. When the
request arrives from a known cloud or AI-provider ASN the server refuses to
guess and returns `400 location_required`, whose `hint` is the same call with
`location` filled in. Ask the user for a city or ZIP and resend.

`GET /where` reports what the server would infer for this caller: `lat`, `lng`,
`label`, `city`, `region`, `country`, `postal_code`, `source`
(`explicit` | `gazetteer` | `ip` | `unknown`), `confidence`, `accuracy_km`,
`guessed`, `is_datacenter`, and the `network` ASN and organization. Call it
before searching "near me" and confirm the label with the user.

Coordinates are fuzzed to roughly 100 m before storage and pages show a
city-level label, because a listing is someone's home.

## GET /search

```bash
curl 'https://curb.sale/search?q=sofa&near=Austin,TX&radius_km=40&max_price=30000'
```

Parameters: `q`, `near` or `lat`+`lng`, `radius_km` (default 40, max 500),
`min_price`, `max_price`, `category`, `condition`, `sold=0|1`, `limit` (default
20, max 50), `cursor`.

`min_price` also answers to `price_min` and `min`; `max_price` also answers to
`price_max`, `max`, `under` and `budget`. Both are **minor units**, so
`max_price=30000` is a $300 ceiling and `min_price=free` is `0`. A value that is
not an amount at all is ignored rather than fatal.

A `max_price` filter excludes listings with no stated price: an unstated price
cannot be proven to satisfy a bound.

Ranking is semantic, so a description of the object beats a keyword guess — a
query for "desk" returns a bureau, and "small table for a hallway" outranks
"table".

When the caller's location is unknown, search does not fail — it returns
national results ranked by recency plus a `next` saying to ask the user for a
city.

### Response

`/search.json` returns `{query, meta, items, next}`.

- `query` echoes what was parsed, including `min_price_cents` and
  `max_price_cents`. **Read these back to confirm a budget was understood.**
- `meta` carries `location_used` (the full `/where` object), `location_source`,
  `location_confidence`, `location_guessed`, `count`, `has_more`, `next_cursor`
  and an `indexing` note.
- `items` are listings: `id`, `url`, `title`, `description`, `price` (formatted
  string, or null), `price_cents`, `currency`, `is_free`, `accepts_offers`,
  `category`, `condition`, `location`, `city`, `region`, `country`,
  `postal_code`, `lat`, `lng`, `distance_km`, `status`, `searchable`, `photo`,
  `photos[]` (`url`, `alt`, `width`, `height`), `inferred`, `contact_url`,
  `created_at`, `updated_at`, `expires_at`, `sold_at`, `view_count`.
- `next` is prose telling the caller what to do with the results.

`GET /l/{id}.json` returns `{listing, next}` with the same listing shape.

## Managing a listing

The `edit_token` does all of it:

```bash
curl -X PATCH  https://curb.sale/l/{id}       -H 'authorization: Bearer curb_e_…' \
  -H 'content-type: application/json' -d '{"price_cents":12500}'
curl -X POST   https://curb.sale/l/{id}/sold  -H 'authorization: Bearer curb_e_…'
curl -X POST   https://curb.sale/l/{id}/renew -H 'authorization: Bearer curb_e_…'
curl -X DELETE https://curb.sale/l/{id}       -H 'authorization: Bearer curb_e_…'
```

The token is accepted three ways, in this order: the `authorization: Bearer`
header, a `?token=` query parameter, or an `edit_token` field in the JSON body.
The last two exist for agents that cannot set headers.

Editable fields, as the server itself lists them on a `nothing_to_update`:
`title`, `body`, `price`, `price_cents`, `currency`, `free`, `accepts_offers`,
`category`, `condition`, `location`, `lat`, `lng`. `body` also answers to
`description`, `text` and `details`; `location` to `near` and `place`;
`accepts_offers` to `obo`; `free` to `is_free`. `lat` and `lng` only take effect
sent together — `lat` alone is ignored and the call comes back
`nothing_to_update`. Setting a field to `null` clears it.

**Send `price_cents` as a whole number of minor units:** `{"price_cents":12500}`
is $125.00. A numeric string is coerced — it has to be, since a form field and a
query parameter are both strings — but the JSON number is the one spelling that
has never been ambiguous on any version of this server. `price` takes the same
integer, and additionally a string a person typed: `"$150"` and `"free"` both
work.

The two names then diverge, in the opposite direction from intuition, and this
is worth knowing before you reach for the shorter one. `price_cents` runs through
the money parser, so `"1.5k"` **is** accepted there and means $1,500. `price`
runs through the prose extractor, which wants a currency cue: `price: "1.5k"` and
`price: "150"` are both rejected with `invalid_field` and "Use a number of USD,
\"$150\", or \"free\"." Scoped to `price` — do not generalise it to
`price_cents`. Sending `price_cents` as a whole number sidesteps the whole
question, which is why every example here does.

Moderation applies to edits, not only to creation — an edit into a prohibited
category is refused and recorded. POST to `/l/{id}` is not an edit verb and
returns `method_not_allowed`.

## Contacting a seller

```bash
curl -sX POST https://curb.sale/l/{id}/contact -H 'content-type: application/json' \
  -d '{"message":"Still available?","reply_to":"me@example.com"}'
```

`message` also answers to `text`, `body` and `note`; `reply_to` to `replyTo`,
`email` and `contact_email`. Form-encoded bodies work as well as JSON. The
message limit is **2000 characters**.

With `reply_to`, the seller replies by email through a relay and neither side
learns the other's address. Without it, the response carries `thread_url` and
`buyer_token` to poll, keeping the buyer accountless. **`buyer_token` is also
returned exactly once** — save it, or save the thread page URL, before doing
anything else.

Phone numbers, emails and URLs are stripped from listing bodies and from opening
messages, in both directions. The relay exists so they are not needed.

### Reading and answering — GET /l/{id}/messages, /threads/{tid}, POST /threads/{tid}/reply

These three are live. They are not on `/index.md`'s field list in any detail, so
read this section rather than assuming the brief covered them.

```bash
# the seller's inbox: every thread on one listing
curl -s https://curb.sale/l/{id}/messages -H 'authorization: Bearer curb_e_…'
# one thread, from either side
curl -s https://curb.sale/threads/{tid} -H 'authorization: Bearer <buyer_token|edit_token>'
# reply, from either side
curl -sX POST https://curb.sale/threads/{tid}/reply \
  -H 'authorization: Bearer <buyer_token|edit_token>' \
  -H 'content-type: application/json' -d '{"message":"..."}'
```

Markdown by default on both GETs; `.json` or `Accept: application/json` for JSON.
`/l/{id}/messages.json` returns `{listing, thread_count, awaiting_reply,
threads[], next}`; a thread carries `thread_id`, `thread_url`, `buyer_label`
(`buyer-9mva` — no address on either side), `status`, `message_count`,
`awaiting_seller`, `created_at`, `last_message_at` and `messages[]`.
`/threads/{tid}.json` returns `{role, listing, thread, next}`, where `role` is
`buyer` or `seller` depending on which token was presented.

A reply returns 201 with the stored message, `redacted[]` naming what was
removed, and `delivery` for the other side. Errors: `409 thread_closed`,
`413 message_too_long` (2000), `422 message_is_only_contact_info`.

Budgets, per rolling hour: 10 contacts per caller and 25 per listing, 40 replies
per thread.

**Nothing is emailed to an unclaimed seller.** A `delivery.{seller|buyer}.reason`
of `no_address_on_file` means the message is in the thread and will be seen at
the manage link, and no notification was sent or is pending. Read that field
rather than assuming.

## Errors

Every error is `{error, code, message, hint, docs_url}`, plus `retry_after` on a
429. `error` and `code` carry the same value because clients look for either.
`hint` is a complete corrected curl, not prose — run it.

| Code | Status | What to do |
|---|---|---|
| `missing_content` | 400 | Send `text` or `photo`. At least one. |
| `location_required` | 400 | Datacenter IP. Ask for a city or ZIP, send `location`. |
| `malformed_json` | 400 | Body is not valid JSON. Check the quoting. |
| `invalid_field` | 400 | A PATCH field failed validation; `fields` names which. |
| `nothing_to_update` | 400 | The PATCH body had no editable field; `editable` lists them. |
| `missing_message` | 400 | A contact request needs `message`. |
| `message_too_long` | 413 | 2000 characters max. Same code on `/contact` and on a thread reply. |
| `invalid_reply_to` | 400 | `reply_to` is not a usable address. Omit it and poll the thread. |
| `edit_token_required` | 401 | Send `authorization: Bearer curb_e_…`. Listing routes. |
| `missing_token` | 401 | Same fix, but this is the code the relay routes (`/l/{id}/messages`, `/threads/{tid}`) return. |
| `invalid_token` | 401 | A thread token did not match that thread. |
| `edit_token_invalid` | 403 | Wrong token for this listing. It was shown once, at create. |
| `prohibited_content` | 403 / 422 | Category is not listable. See `/prohibited`. |
| `not_found` / `listing_not_found` | 404 | No such listing. Ids are case-sensitive. |
| `method_not_allowed` | 405 | POST to a listing is not an edit. Use PATCH. |
| `photo_too_large` | 413 | 20 MB per photo, 48 MB per request, 6 photos. Downscale. |
| `rate_limited` | 429 | Wait `retry_after` seconds. |
| `proof_of_work_required` | 429 | Solve the challenge and resend with `x-curb-pow`. |

Codes outside this table exist. The shape and the `hint` are the contract, not
the enumeration.

A 429 issues an executable proof-of-work challenge rather than a CAPTCHA, since
the primary caller cannot solve a CAPTCHA: find a nonce where
`sha256(challenge + nonce)` has the stated number of leading zero bits, then
resend the identical request with `x-curb-pow: <challenge>.<nonce>`. The
response body carries a runnable hint. Rate limiting keys on ASN plus a poster
fingerprint, never raw IP, so one hosted agent's users do not share a ban, and a
first listing never sees a challenge.

**A bare 403 with no JSON envelope is not from curb.sale.** See
`blocked-egress.md`.

## Rules

Physical goods only. No weapons, drugs, adult content or personals,
counterfeits, live animals, stolen goods, services, or crypto. Full list at
`https://curb.sale/prohibited`.

Bulk mirroring, reselling access, using the corpus as training data, posting for
anyone who did not ask, and mass-contacting sellers are all out of bounds; the
full policy is at `https://curb.sale/agents.md`.

Listings expire in 30 days unless claimed. Bodies are plain text; HTML is
escaped and never rendered. Whoever operates the agent is the poster of record.
