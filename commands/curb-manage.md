---
name: curb-manage
description: Run a curb.sale listing you already posted — read buyer messages, reply, change the price, renew, mark it sold, or take it down.
---

Manage the curb.sale listing described in `$ARGUMENTS`.

Activate the `curb-sale` skill and follow it. Everything here needs that
listing's `edit_token`, returned exactly once at creation.

**Find the token before anything else.** Look for it in this conversation, or ask
the user for the `manage_url` they were given — the token is the part after
`#t=`. If neither exists, the listing cannot be managed through the API at all.
Say that plainly and stop. Do not guess a token, and do not offer to reset one:
nothing can.

Then do the smallest thing that answers what was asked.

**"Did anyone write?"**

```bash
curl -s https://curb.sale/l/{id}/messages -H 'authorization: Bearer <edit_token>'
```

Markdown by default; `.json` gives `{listing, thread_count, awaiting_reply,
threads[], next}`. `awaiting_seller` on a thread is the queue in one boolean.
Buyers show up as a label like `buyer-9mva` — there is no address on either side.
Report who is waiting and what they asked; do not answer for the user.

**Reply.**

```bash
curl -sX POST https://curb.sale/threads/{thread_id}/reply \
  -H 'authorization: Bearer <edit_token>' -H 'content-type: application/json' \
  -d '{"message":"Yes, still here. Saturday 10am works."}'
```

Send the user's own words. Phone numbers, emails and links are stripped in both
directions and never stored, so propose a public place and a time instead.

**Change something.** `price_cents` is a whole number of minor units — `12500` is
$125.00.

```bash
curl -X PATCH https://curb.sale/l/{id} -H 'authorization: Bearer <edit_token>' \
  -H 'content-type: application/json' -d '{"price_cents":12500}'
```

Editable: `title`, `body`, `price`, `price_cents`, `currency`, `free`,
`accepts_offers`, `category`, `condition`, `location`, `lat`, `lng`. `lat` and
`lng` only count when sent together. `null` clears a field. Moderation applies to
edits too.

**Renew** for another 30 days: `POST /l/{id}/renew` with the same header.

**Mark sold — ask the user to confirm first, because it cannot be undone.**
`status` is not editable and renewing a sold listing leaves it sold, so the only
way back is to delete and post again, losing the URL, the view count and every
open conversation.

```bash
curl -sX POST https://curb.sale/l/{id}/sold -H 'authorization: Bearer <edit_token>'
```

**Delete** is also permanent — the URL 404s and the photos go. Marking sold is
almost always what the user means; reach for delete only when they say the
listing itself was a mistake.

Afterwards, tell the user what changed in one line, and what it now costs to
change back. Never write the `edit_token` into a file, a commit or any channel
with more than one reader: it is the seller's credential, not this agent's.

`https://curb.sale/index.md` is the live contract in under 4,500 characters.
Where anything here disagrees with the server, the server is right.
