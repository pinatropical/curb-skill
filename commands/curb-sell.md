---
name: curb-sell
description: List something for sale on curb.sale — one call, no account, live URL back in seconds.
---

List the thing described in `$ARGUMENTS` on curb.sale.

Activate the `curb-sale` skill and follow it before calling anything; it
carries the field semantics, the once-only tokens, and the recovery for a
sandbox that blocks the request.

Before posting:

1. **Establish the location.** Ask the user for a city or ZIP if it is not
   already known from the conversation. Do not use this machine's IP location —
   it is the agent's, not the user's, and from a datacenter it is simply wrong.
   Omitting `location` there does not fall back to a guess: the server answers
   `400 location_required` and asks for the city, so nothing is posted until
   you have one.
2. **Use the user's own words** as `text`. Do not rewrite them into ad copy;
   the server infers a title and category and reports what it wrote.
3. **Do not invent a price, and do not add one the user did not state.** The
   server parses the amount out of the `text` that was sent; with no amount
   anywhere the price stays unstated, which is not the same as free. No model
   ever writes a price, so omitting the field does not mean the server guesses
   one. If the user named a price, send it in **cents** — `$150` is
   `price_cents=15000`.
4. **Attach the photo** if one was given or is present in the conversation. A
   photo is worth more than any description here. Up to 6, 20 MB each, 48 MB
   per request.

After the 201, tell the user:

- the listing is **live now** at `url`, with the link
- `manage_url`, which edits, marks sold or deletes with no login
- exactly which fields were `inferred`, so they can correct them — the price is
  never among them, so state separately what price was set and where it came
  from, or that the listing has none
- any `warning` on the response, which is how a photo past the sixth is reported
- that it expires in 30 days unless it is claimed, which means opening
  `claim_url`, giving an email, and typing back the code sent there

`edit_token` and `claim_url` are shown once and cannot be recovered. Surface
them in the reply rather than only keeping them in context, and copy them byte
for byte — never shorten, redact or elide any part of one.

If the POST is refused with `403 host_not_allowed`, or with any 403 that is not
JSON, the local sandbox blocked it and curb.sale never saw the request. Do not
retry. Follow `references/blocked-egress.md`: allowlist `curb.sale`, hand the
user the curl that `scripts/curb.sh --dry-run sell …` prints, or give them the
prefilled `https://curb.sale/new?...` page.

`https://curb.sale/index.md` is the live contract in under 4,500 characters.
Where anything here disagrees with the server, the server is right.
