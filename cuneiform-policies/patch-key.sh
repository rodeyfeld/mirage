#!/usr/bin/env bash
# Writes one value you choose (a third-party token, a password you pick) into
# cuneiform at galaxy-kv/prod/<app>, through the cuneiform-0 pod on galaxy.
#
#   patch-key.sh <app> <key> [ENV_VAR]
#
# The value comes from $ENV_VAR when it's named and set, else a hidden prompt.
# The Bao token comes from $BAO_TOKEN, else a hidden prompt. Both travel over
# ssh on stdin, so neither lands on a command line or in shell history.
#
# e.g. patch-key.sh mycelia claude_code_oauth_token CLAUDE_CODE_OAUTH_TOKEN
set -euo pipefail

[ $# -ge 2 ] || { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
app="$1" key="$2" from="${3:-}"

[[ "$app" =~ ^[a-z0-9-]+$ && "$key" =~ ^[a-z0-9_]+$ ]] ||
  { echo "app must be [a-z0-9-], key [a-z0-9_]" >&2; exit 2; }

if [ -n "$from" ] && [ -n "${!from:-}" ]; then
  value="${!from}"
  echo "value: from \$$from"
else
  read -rsp "value for $key: " value; echo
fi
[ -n "$value" ] || { echo "empty value" >&2; exit 1; }

token="${BAO_TOKEN:-}"
[ -n "$token" ] || { read -rsp "Bao token: " token; echo; }
[ -n "$token" ] || { echo "empty Bao token" >&2; exit 1; }

# First line is the Bao token; the rest is the value, read by `bao kv patch`'s `=-`.
printf '%s\n%s' "$token" "$value" |
  ssh -T galaxy "k3s kubectl -n galaxy exec -i cuneiform-0 -- sh -c 'read -r t; BAO_ADDR=http://127.0.0.1:8200 BAO_TOKEN=\$t bao kv patch galaxy-kv/prod/$app $key=-'"
