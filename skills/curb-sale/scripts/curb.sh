#!/usr/bin/env bash
#
# curb.sh — the curb.sale calls with the quoting already right.
#
# Requires: curl. `contact` and `edit` also require python3, which builds their
# JSON with a real encoder rather than string concatenation.
#
# Every subcommand prints the raw response and interprets nothing, because the
# response's own `next` field is the instruction and it should reach the caller
# intact.
#
# Two things this script does beyond curl:
#
#   --dry-run   prints the curl instead of running it. This is the whole
#               recovery when the local sandbox blocks curb.sale: the command it
#               prints is the one to hand to the user.
#
#   sandbox detection. A refusal by the local egress proxy and a refusal by
#               curb.sale look alike and mean opposite things — one is worth
#               retrying, the other never is. See references/blocked-egress.md.
#
# This script keeps no state, and that is a decision rather than an omission.
# The edit_token, buyer_token and claim_url belong to the seller and the buyer;
# the agent running this is holding them for someone else. A file of other
# people's listing credentials sitting in a working directory is the one leak on
# this service that matters — a listing is a home address, fuzzed to 100m. Do not
# add a cache, a ~/.curb/ directory, or a state.json keyed by listing id.
# Everything is printed and nothing is written.

set -euo pipefail

ORIGIN="${CURB_ORIGIN:-https://curb.sale}"
DRY_RUN="${CURB_DRY_RUN:-}"

usage() {
  cat >&2 <<'USAGE'
usage:
  curb.sh sell    [--text TEXT] [--photo FILE]... [--location "Austin, TX"] [--price CENTS]
  curb.sh search  [QUERY] [--near "Austin, TX"] [--radius-km 40] [--max-price CENTS]
                  [--min-price CENTS] [--category C] [--condition C] [--limit N]
  curb.sh get     ID
  curb.sh where
  curb.sh contact ID --message TEXT [--reply-to EMAIL]
  curb.sh inbox   ID  --token curb_e_...
  curb.sh thread  TID --token curb_b_... | curb_e_...
  curb.sh reply   TID --token curb_b_... | curb_e_... --message TEXT
  curb.sh edit    ID --token curb_e_... [--price CENTS] [--title T] [--description D]
  curb.sh sold    ID --token curb_e_...
  curb.sh renew   ID --token curb_e_...
  curb.sh delete  ID --token curb_e_...

global:
  --dry-run   Print the curl instead of running it. Hand that command to the
              user when this machine cannot reach curb.sale.

`sell` needs at least one of --text or --photo; both is better. --photo may be
repeated up to 6 times.

--location is optional but close to required: without it the server geolocates
THIS machine's IP, which is the agent's location and not the user's, and from a
datacenter it returns 400 location_required rather than guessing. Ask the user.

EVERY price on this API is in CENTS. --price 300 is $3.00, on a listing and on a
search bound alike. The one exception is a value a person plainly typed — a
currency symbol, a decimal point, a `k`, or the word free — so "$3", "3.00" and
300 all mean $3.00, and "1.5k" means $1,500.

Set CURB_ORIGIN to point at a local dev server. Set CURB_DRY_RUN=1 for --dry-run.
USAGE
  exit 2
}

need_python() {
  command -v python3 >/dev/null 2>&1 || {
    echo "curb.sh: python3 is required to build the JSON body for this subcommand." >&2
    echo "curb.sh: re-run with --dry-run and adapt the printed curl by hand." >&2
    exit 2
  }
}

# Print a runnable command. The output is for a person to paste into their own
# shell, so it is single-quoted POSIX rather than `printf %q`, whose backslash
# soup and `$'...'` are correct, bash-only, and unreadable. Single quotes hold a
# newline literally, so a multi-line listing survives the copy.
shquote() {
  case "$1" in
    "" ) printf "''" ;;
    *[!A-Za-z0-9_@%+=:,./-]* ) printf "'%s'" "${1//\'/\'\\\'\'}" ;;
    * ) printf '%s' "$1" ;;
  esac
}

print_command() {
  local out="curl" arg
  for arg in "$@"; do out+=" $(shquote "$arg")"; done
  printf '%s\n' "$out"
}

# Separate "the sandbox refused" from "curb.sale refused". A curb.sale error is
# always JSON carrying a `code`; anything else on a 4xx came from this machine.
run() {
  if [[ -n "$DRY_RUN" ]]; then
    print_command -sS "$@"
    return 0
  fi

  local response status body errfile
  errfile="$(mktemp)"
  if ! response="$(curl -sS -w $'\n%{http_code}' "$@" 2>"$errfile")"; then
    cat >&2 <<EOF
curb.sh: the request did not complete. curb.sale never received it.

  $(cat "$errfile")

This is almost certainly the local network sandbox, not curb.sale. Add curb.sale
to the egress allowlist (sandbox.network.allowedDomains in ~/.claude/settings.json),
or re-run with --dry-run and give the printed command to the user. Retrying as-is
will not help.
EOF
    rm -f "$errfile"
    return 7
  fi
  rm -f "$errfile"

  status="${response##*$'\n'}"
  body="${response%$'\n'*}"

  if [[ "$status" == "403" || "$status" == "407" ]] && ! printf '%s' "$body" | grep -q '"code"'; then
    cat >&2 <<EOF
curb.sh: HTTP $status with no curb.sale error envelope — this came from the local
egress proxy, not from curb.sale. The request never left this machine.

  $body

Add curb.sale to the egress allowlist, or re-run with --dry-run and hand the
printed command to the user. Do not retry.
EOF
    return 7
  fi

  printf '%s\n' "$body"
  [[ "$status" =~ ^2 ]] || return 1
}

cmd_sell() {
  local text="" location="" price="" args=() photos=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --text) text="$2"; shift 2 ;;
      --photo) photos+=("$2"); shift 2 ;;
      --location) location="$2"; shift 2 ;;
      # `price` and `price_cents` mean the same thing on the current server, but
      # only `price_cents` has meant cents on every version of it. Sending that
      # name costs nothing and cannot be read as dollars by an older deploy.
      --price|--price-cents) price="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  [[ -n "$text" || ${#photos[@]} -gt 0 ]] || usage

  [[ -n "$text" ]] && args+=(-F "text=$text")
  local photo
  for photo in ${photos[@]+"${photos[@]}"}; do
    [[ -f "$photo" ]] || { echo "curb.sh: no such file: $photo" >&2; exit 2; }
    args+=(-F "photo=@$photo")
  done
  [[ -n "$location" ]] && args+=(-F "location=$location")
  [[ -n "$price" ]] && args+=(-F "price_cents=$price")

  run -X POST "$ORIGIN/sell" "${args[@]}"
}

cmd_search() {
  # The query is optional: "anything free nearby" is a real search with no
  # keywords, and taking a leading --flag as the query would silently search for
  # the string "--near".
  local args=(-G "$ORIGIN/search.json")
  if [[ $# -gt 0 && "$1" != --* ]]; then
    args+=(--data-urlencode "q=$1")
    shift
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --near) args+=(--data-urlencode "near=$2"); shift 2 ;;
      --radius-km) args+=(--data-urlencode "radius_km=$2"); shift 2 ;;
      # Cents, like every other price on this API. --max-price 30000 is $300.
      --max-price) args+=(--data-urlencode "max_price=$2"); shift 2 ;;
      --min-price) args+=(--data-urlencode "min_price=$2"); shift 2 ;;
      --category) args+=(--data-urlencode "category=$2"); shift 2 ;;
      --condition) args+=(--data-urlencode "condition=$2"); shift 2 ;;
      --limit) args+=(--data-urlencode "limit=$2"); shift 2 ;;
      --cursor) args+=(--data-urlencode "cursor=$2"); shift 2 ;;
      --sold) args+=(--data-urlencode "sold=1"); shift ;;
      *) usage ;;
    esac
  done
  run "${args[@]}"
}

cmd_get() {
  [[ $# -eq 1 && "$1" != --* ]] || usage
  run "$ORIGIN/l/$1.json"
}

cmd_where() {
  [[ $# -eq 0 ]] || usage
  run "$ORIGIN/where.json"
}

cmd_contact() {
  [[ $# -gt 0 && "$1" != --* ]] || usage
  local id="$1"; shift
  local message="" reply_to=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --message) message="$2"; shift 2 ;;
      --reply-to) reply_to="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  [[ -n "$message" ]] || usage
  need_python

  local payload
  payload="$(json_object message "$message" ${reply_to:+reply_to "$reply_to"})"
  run -X POST "$ORIGIN/l/$id/contact" -H 'content-type: application/json' -d "$payload"
}

# The seller's inbox: every thread on one listing, with the edit_token.
cmd_inbox() {
  [[ $# -gt 0 && "$1" != --* ]] || usage
  local id="$1"; shift
  local token=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --token) token="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  [[ -n "$token" ]] || usage
  run "$ORIGIN/l/$id/messages.json" -H "authorization: Bearer $token"
}

# One thread, from either side. The buyer_token and the listing's edit_token are
# both accepted here and the response's `role` says which one was used.
cmd_thread() {
  [[ $# -gt 0 && "$1" != --* ]] || usage
  local id="$1"; shift
  local token=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --token) token="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  [[ -n "$token" ]] || usage
  run "$ORIGIN/threads/$id.json" -H "authorization: Bearer $token"
}

cmd_reply() {
  [[ $# -gt 0 && "$1" != --* ]] || usage
  local id="$1"; shift
  local token="" message=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --token) token="$2"; shift 2 ;;
      --message) message="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  [[ -n "$token" && -n "$message" ]] || usage
  need_python

  local payload
  payload="$(json_object message "$message")"
  run -X POST "$ORIGIN/threads/$id/reply" -H "authorization: Bearer $token" \
    -H 'content-type: application/json' -d "$payload"
}

cmd_edit() {
  [[ $# -gt 0 && "$1" != --* ]] || usage
  local id="$1"; shift
  local token="" fields=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --token) token="$2"; shift 2 ;;
      # Cents, and emitted as a JSON number — see json_object.
      --price|--price-cents)
        [[ "$2" =~ ^[0-9]+$ ]] || {
          echo "curb.sh: --price takes whole cents, e.g. 12500 for \$125.00. Got: $2" >&2
          exit 2
        }
        fields+=("#price_cents" "$2"); shift 2 ;;
      --title) fields+=(title "$2"); shift 2 ;;
      --description) fields+=(description "$2"); shift 2 ;;
      --location) fields+=(location "$2"); shift 2 ;;
      --category) fields+=(category "$2"); shift 2 ;;
      --condition) fields+=(condition "$2"); shift 2 ;;
      *) usage ;;
    esac
  done
  [[ -n "$token" && ${#fields[@]} -gt 0 ]] || usage
  need_python

  local payload
  payload="$(json_object "${fields[@]}")"
  run -X PATCH "$ORIGIN/l/$id" -H "authorization: Bearer $token" \
    -H 'content-type: application/json' -d "$payload"
}

# sold, renew and delete are one shape: an id and the edit_token, no body.
token_command() {
  local method="$1" suffix="$2"; shift 2
  [[ $# -gt 0 && "$1" != --* ]] || usage
  local id="$1"; shift
  local token=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --token) token="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  [[ -n "$token" ]] || usage
  run -X "$method" "$ORIGIN/l/$id$suffix" -H "authorization: Bearer $token"
}

# Build JSON with a real encoder rather than string concatenation: a message is
# free text from a person and will eventually contain a quote or a newline.
#
# A key prefixed with `#` is emitted as a JSON number. That is not decoration:
# `price_cents` is a whole number of minor units, and the JSON number is the one
# spelling of it that has been unambiguous on every version of the server. The
# current server also coerces the numeric string, because a form field and a
# query parameter are both strings and demanding JSON made the field unsettable
# from either — but the single most likely edit an agent ever makes is correcting
# a price, and it should not depend on which deploy is answering.
json_object() {
  python3 -c '
import json, sys
a = sys.argv[1:]
out = {}
for k, v in zip(a[::2], a[1::2]):
    if k.startswith("#"):
        out[k[1:]] = int(v)
    else:
        out[k] = v
print(json.dumps(out))' "$@"
}

argv=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) argv+=("$arg") ;;
  esac
done
set -- ${argv[@]+"${argv[@]}"}

[[ $# -gt 0 ]] || usage
subcommand="$1"; shift
case "$subcommand" in
  sell) cmd_sell "$@" ;;
  search) cmd_search "$@" ;;
  get) cmd_get "$@" ;;
  where) cmd_where "$@" ;;
  contact) cmd_contact "$@" ;;
  inbox) cmd_inbox "$@" ;;
  thread) cmd_thread "$@" ;;
  reply) cmd_reply "$@" ;;
  edit) cmd_edit "$@" ;;
  sold) token_command POST /sold "$@" ;;
  renew) token_command POST /renew "$@" ;;
  delete) token_command DELETE "" "$@" ;;
  -h|--help|help) usage ;;
  *) usage ;;
esac
