#!/usr/bin/env bash
# One-time: gives Claude a write-only Bao token. Run it with an admin token.
#
#   claude-token.sh [--force]
#
# Writes the `claude-writer` policy (claude-writer.hcl), creates a periodic
# token on it (30 days, renewed whenever patch-key.sh uses it) and saves it to
# ~/.config/cuneiform/env (mode 600) as BAO_TOKEN. The admin token comes from
# $BAO_TOKEN, else a hidden prompt; it goes over ssh on stdin. Neither token is
# printed. --force replaces an existing env file (the old token isn't revoked).
set -euo pipefail

out="$HOME/.config/cuneiform/env"
policy="$(dirname "$0")/claude-writer.hcl"

if [ -e "$out" ] && [ "${1:-}" != --force ]; then
  echo "$out exists; rerun with --force to replace it" >&2
  exit 1
fi

admin="${BAO_TOKEN:-}"
[ -n "$admin" ] || { read -rsp "admin Bao token: " admin; echo; }
[ -n "$admin" ] || { echo "empty Bao token" >&2; exit 1; }

# First line is the admin token; the rest is the policy, read by `policy write -`.
token="$(
  { printf '%s\n' "$admin"; cat "$policy"; } |
    ssh -T galaxy "k3s kubectl -n galaxy exec -i cuneiform-0 -- sh -c 'read -r t; export BAO_ADDR=http://127.0.0.1:8200 BAO_TOKEN=\$t; bao policy write claude-writer - >&2 && bao token create -policy=claude-writer -period=720h -display-name=claude -field=token'"
)"
[ -n "$token" ] || { echo "no token came back" >&2; exit 1; }

mkdir -p "$(dirname "$out")"
(umask 077 && printf 'BAO_TOKEN=%s\n' "$token" > "$out")
echo "saved to $out"
