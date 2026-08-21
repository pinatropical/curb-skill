---
name: curb-contact
description: Message the seller of a curb.sale listing and follow the reply — no account on either side, and neither party learns the other's email address.
---

Reach the seller of the listing named in `$ARGUMENTS`.

Activate the `curb-sale` skill and follow it. This writes to a real person who
will end up standing in a driveway, so **ask the user before sending**, and
send their words rather than a template.

```bash
curl -sX POST https://curb.sale/l/{id}/contact -H 'content-type: application/json' \
  -d '{"message":"Still available? I could pick up Saturday morning.","reply_to":"me@example.com"}'
```

`reply_to` is the **user's own** address. Never substitute one, never invent one,
and never use the address of whoever operates this agent. With it, the seller
answers by email through a relay and neither side learns the other's address.

Without `reply_to` the call still works and the buyer stays entirely
accountless. The 201 then carries:

- `thread_page_url` — the link for the user, of the form
  `https://curb.sale/t/{thread_id}#t=<buyer_token>`. It opens the conversation in
  a browser with no login; the token is in the `#` fragment, so it never reaches
  the server. Copy it whole.
- `buyer_token` — polls and replies from a terminal, and is returned **exactly
  once**:

```bash
curl -s https://curb.sale/threads/{tid} -H 'authorization: Bearer <buyer_token>'
curl -sX POST https://curb.sale/threads/{tid}/reply \
  -H 'authorization: Bearer <buyer_token>' -H 'content-type: application/json' \
  -d '{"message":"Great — see you at 10."}'
```

Give both to the user verbatim before summarising anything else.

Read `delivery.seller` back before reporting success. `reason:
"no_address_on_file"` means this seller has no address with us — usually because
the listing was never claimed: the message is in the thread and they will see it
at their manage link, but nothing was emailed and nothing will chase them. Tell
the user that instead of promising a fast reply.

Messages cap at 2000 characters (`413 message_too_long`). Phone numbers, emails
and links are stripped in both directions, so one that is nothing but contact
details is refused with `422 message_is_only_contact_info` — propose a public
place and a time instead.

One listing, one message, when the user asks for it. Working down a page of
search results is out of bounds: https://curb.sale/agents.md.

`https://curb.sale/index.md` is the live contract in under 4,500 characters.
Where anything here disagrees with the server, the server is right.
