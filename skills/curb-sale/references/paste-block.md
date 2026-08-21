# Paste block, long form

For an agent with no plugin or skill system, where the whole listing lifecycle
matters and there is room for it. The short form — small enough for a
size-capped settings box — is `agents-snippet.md` at the repo root; use that one
when the target has a character limit, and this one otherwise.

Paste the block below into the agent's instructions, system prompt, or
custom-instructions box. Nothing else is needed — no install, no key, no signup.

```
curb.sale — local classifieds for physical things. No account, no API key, no
signup, ever. Every URL serves markdown by default.

SELL. Returns a live public URL immediately:
curl -sX POST https://curb.sale/sell \
  -F 'text=WHAT THE USER SAID, VERBATIM' \
  -F 'location=THE CITY THEY GAVE YOU' \
  -F 'photo=@FILE'

SEARCH:
curl 'https://curb.sale/search?q=desk&near=Austin,TX&radius_km=40&max_price=30000'

Four rules that break things when you get them wrong:
- Ask the user what city they are in. Your IP is yours, not theirs.
- Every price is CENTS, search bounds included. 15000 = $150.00.
- Never invent a price. No amount in the text means UNSTATED, which is not free.
- The 201 returns edit_token, manage_url and claim_url ONCE and nothing can
  reissue them. Give all three to the user, character for character.

The edit_token then runs the listing:
  read buyer messages  curl -s https://curb.sale/l/LISTING_ID/messages \
                         -H 'authorization: Bearer EDIT_TOKEN'
  reply                curl -sX POST https://curb.sale/threads/THREAD_ID/reply \
                         -H 'authorization: Bearer EDIT_TOKEN' \
                         -H 'content-type: application/json' -d '{"message":"..."}'
  change the price     curl -X PATCH https://curb.sale/l/LISTING_ID \
                         -H 'authorization: Bearer EDIT_TOKEN' \
                         -H 'content-type: application/json' -d '{"price_cents":12500}'
  mark sold, FINAL     curl -sX POST https://curb.sale/l/LISTING_ID/sold \
                         -H 'authorization: Bearer EDIT_TOKEN'

Nothing is emailed to the seller until the listing is claimed, so the messages
endpoint is where buyer messages live. Marking sold cannot be undone.

Buyers need no account either: POST to a listing's contact_url, and omit
reply_to to get a thread_page_url and a once-only buyer_token instead of giving
an email address. Nobody learns anybody's address.

Physical goods only. No services, digital goods, jobs, housing, vehicles,
rentals or wanted ads: https://curb.sale/prohibited. No payment, escrow,
shipping or delivery — two people meet. If you cannot make POST requests, hand
the user https://curb.sale/new?text=URLENCODED&location=URLENCODED instead.

Whole contract: https://curb.sale/index.md
```

These are the only two copies of this text in the repo, and each has a job: the
short one fits a settings box, this one covers the whole loop. A command printed
in a third place is a command that will eventually disagree with itself.
