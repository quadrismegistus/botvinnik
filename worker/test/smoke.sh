#!/usr/bin/env bash
# Manual smoke test against a running `npm run dev` (default localhost:8787).
# Exercises the create / update / stale-etag / 404 paths the M1 spec calls for.
#   Terminal 1: npm run dev
#   Terminal 2: ./test/smoke.sh
set -euo pipefail

BASE="${1:-http://localhost:8787}"
ID="smoke$(printf '%016d' "${RANDOM}${RANDOM}")"
URL="$BASE/b/$ID"
pass=0 fail=0

check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "  ok   $1 ($3)"; pass=$((pass+1));
  else echo "  FAIL $1 — expected $2, got $3"; fail=$((fail+1)); fi
}
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
etag_of() { curl -s -D - -o /dev/null "$@" | tr -d '\r' | awk -F': ' 'tolower($1)=="etag"{print $2}'; }

echo "health:"
check "GET /" 200 "$(code "$BASE/")"

echo "get-missing:"
check "GET absent -> 404" 404 "$(code "$URL")"

echo "create:"
ETAG1=$(etag_of -X PUT -H 'If-None-Match: *' --data 'ciphertext-v1' "$URL")
check "create -> has etag" "yes" "$([ -n "$ETAG1" ] && echo yes || echo no)"
check "GET after create -> 200" 200 "$(code "$URL")"

echo "create-conflict:"
check "second create -> 412" 412 "$(code -X PUT -H 'If-None-Match: *' --data 'ciphertext-vX' "$URL")"

echo "update:"
check "update w/ current etag -> 200" 200 "$(code -X PUT -H "If-Match: $ETAG1" --data 'ciphertext-v2' "$URL")"

echo "stale-update:"
check "update w/ stale etag -> 412" 412 "$(code -X PUT -H "If-Match: $ETAG1" --data 'ciphertext-v3' "$URL")"

echo "no-precondition:"
check "blind PUT -> 428" 428 "$(code -X PUT --data 'x' "$URL")"

echo
echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]
