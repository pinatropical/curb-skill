---
name: curb-search
description: Find something secondhand nearby on curb.sale — no account, no API key, results with a way to reach the seller.
---

Search curb.sale for what is described in `$ARGUMENTS`.

Activate the `curb-sale` skill and follow it before calling anything; it
carries the price units, the response shape, and the recovery for a sandbox
that blocks the request.

Before searching:

1. **Establish the location.** Ask the user for a city or ZIP unless the
   conversation already names one. Do not use this machine's IP: it is the
   agent's location, not the user's, and from a datacenter it is simply wrong.
   `GET https://curb.sale/where` reports what the server would guess and how
   much it trusts it — treat that as something to confirm, never as the answer.
2. **Describe the object, do not guess keywords.** Ranking is semantic. "small
   table for a hallway" beats "table", and a query for "desk" already returns a
   bureau. Use the user's own description.
3. **Convert any budget to cents.** `max_price` is minor units, so a $300
   ceiling is `max_price=30000`. Passing `300` asks for $3.00 and returns
   nothing. If the user typed the amount themselves — "$300", "1.5k" — that
   string may be passed through as-is and is read the way they meant it.

```bash
curl 'https://curb.sale/search?q=used+desk&near=Austin,TX&radius_km=40&max_price=30000'
```

Markdown by default. Append `.json` for JSON, which returns `{query, meta,
items, next}`. **Read `query.max_price_cents` back** to confirm the budget was
understood before reporting that nothing matched.

Report to the user:

- each item with its `url`, price and distance, in their own units
- that a `max_price` filter hides listings with no stated price, if one was used
- `meta.location_used.label`, when the location was guessed rather than given
- that reaching a seller needs no account: POST the item's `contact_url`

Do not contact a seller as part of a search. That mails a real person, needs the
user's own `reply_to` address, and is a separate decision they should make.

If the search returns nothing, widen `radius_km` or drop the price bound before
concluding the corpus is empty. A brand-new listing is not searchable for about
ten minutes, so a listing just posted in this conversation is expected to be
missing.

If the request is refused with `403 host_not_allowed`, or with any 403 that is
not JSON, the local sandbox blocked it and curb.sale never saw it. Do not retry.
Follow `references/blocked-egress.md`.

`https://curb.sale/index.md` is the live contract in under 4,500 characters.
Where anything here disagrees with the server, the server is right.
