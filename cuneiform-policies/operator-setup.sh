#!/usr/bin/env bash
# One-time, with the root token: sets up the owner's everyday cuneiform login
# so root can stay put away.
#
#   operator-setup.sh [user]     (default user: rodeyfeld)
#
# Enables userpass auth if it isn't, writes the `operator` policy
# (operator.hcl) and creates or updates the user on it (tokens 12h, at most
# 24h). Rerun it to change the password or pick up operator.hcl changes. The
# root token and the new password are prompted for (hidden) and go over ssh on
# stdin. Afterwards: `bao.sh login`.
set -euo pipefail

user="${1:-rodeyfeld}"
[[ "$user" =~ ^[a-z0-9_-]+$ ]] || { echo "bad user name" >&2; exit 2; }
policy="$(dirname "$0")/operator.hcl"

root="${BAO_TOKEN:-}"
[ -n "$root" ] || { read -rsp "root Bao token: " root; echo; }
read -rsp "new password for $user: " pw; echo
read -rsp "again: " pw2; echo
[ "$pw" = "$pw2" ] || { echo "passwords differ" >&2; exit 1; }
[ "${#pw}" -ge 12 ] || { echo "use at least 12 characters" >&2; exit 1; }

# Line 1 root token, line 2 password, the rest the policy.
script='
IFS= read -r t; IFS= read -r pw
export BAO_ADDR=http://127.0.0.1:8200 BAO_TOKEN="$t"
f="$(mktemp)"; trap "rm -f \"$f\"" EXIT
cat > "$f"
bao auth list -format=json | grep -q "\"userpass/\"" || bao auth enable userpass
bao policy write operator "$f"
printf "%s" "$pw" | bao write auth/userpass/users/'"$user"' password=- \
  token_policies=operator token_ttl=12h token_max_ttl=24h
echo "ready: '"$user"' on policy operator"
'
b64="$(printf '%s' "$script" | base64 -w0)"

{ printf '%s\n%s\n' "$root" "$pw"; cat "$policy"; } |
  ssh -T galaxy "k3s kubectl -n galaxy exec -i cuneiform-0 -- sh -c 'eval \"\$(echo $b64 | base64 -d)\"'"

echo "now: $(dirname "$0")/bao.sh login $user"
