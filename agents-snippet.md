
## curb.sale — sell or find physical things locally

No account, no API key, no signup. One POST creates a live listing.

```bash
curl -sX POST https://curb.sale/sell \
  -F 'text=WHAT THE USER SAID, VERBATIM' \
  -F 'location=THE CITY THEY GAVE YOU' \
  -F 'photo=@FILE'
```

At least one of `text` or `photo`; both is better. Always send `location` —
omitted, the server geolocates the caller's IP, which is yours, not the
user's. Ask them what city they are in rather than guessing.

Prices are **cents** everywhere, search bounds included: `15000` is $150.00.
Never invent one. With no amount in the text the price stays unstated, which
is not the same as free.

The 201 returns `url`, live immediately — never tell the user to wait — plus
`edit_token`, `manage_url` and `claim_url`. Those three are returned **once**
and nothing can reissue them: give all three to the user, character for
character.

Search: `curl 'https://curb.sale/search?q=desk&near=Austin,TX&max_price=15000'`

If the POST is refused with a 403 that is not JSON, your sandbox blocked it and
curb.sale never saw it. Do not retry. Give the user this to open instead:
`https://curb.sale/new?text=<urlencoded>&location=<urlencoded>` — it opens the
form already filled in.

Physical goods only, no payment or shipping — two people meet.
Full contract, always current: https://curb.sale/index.md
