#!/usr/bin/env bash
# Runs `bao` against cuneiform without a local bao or a port-forward: each call
# execs into cuneiform-0 on galaxy, with the token on stdin.
#
#   bao.sh login [user]     log in (userpass, default rodeyfeld); caches a 12h
#                           token in ~/.config/cuneiform/session (mode 600)
#   bao.sh <bao args...>    e.g. bao.sh kv list galaxy-kv/prod
#                                echo -n v | bao.sh kv patch galaxy-kv/prod/x k=-
#
# Token: $BAO_TOKEN, else the cached session. Stdin goes to bao when an argument
# is `-` or ends in `=-`. No TTY: commands that prompt won't.
set -euo pipefail

session="$HOME/.config/cuneiform/session"
addr="http://127.0.0.1:8200"

# Runs a script in the pod, shipped base64 so no quoting survives three shells.
remote() {
  local b64
  b64="$(printf '%s' "$1" | base64 -w0)"
  ssh -T galaxy "k3s kubectl -n galaxy exec -i cuneiform-0 -- sh -c 'eval \"\$(echo $b64 | base64 -d)\"'"
}

# POSIX single-quoting for an argument.
q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

if [ "${1:-}" = login ]; then
  user="${2:-rodeyfeld}"
  [[ "$user" =~ ^[a-z0-9_-]+$ ]] || { echo "bad user name" >&2; exit 2; }
  read -rsp "cuneiform password for $user: " pw; echo
  token="$(printf '%s' "$pw" |
    remote "BAO_ADDR=$addr bao write -field=token auth/userpass/login/$user password=-")"
  [ -n "$token" ] || { echo "login failed" >&2; exit 1; }
  mkdir -p "$(dirname "$session")"
  (umask 077 && printf 'BAO_TOKEN=%s\n' "$token" > "$session")
  echo "logged in as $user; token cached for 12h in $session"
  exit 0
fi

[ $# -gt 0 ] || { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

token="${BAO_TOKEN:-}"
if [ -z "$token" ] && [ -r "$session" ]; then
  token="$(sed -n 's/^BAO_TOKEN=//p' "$session")"
fi
[ -n "$token" ] || { echo "no token: run \`$0 login\` (or set BAO_TOKEN)" >&2; exit 1; }

cmd="exec bao" stdin=no
for a in "$@"; do
  cmd+=" $(q "$a")"
  [[ "$a" == - || "$a" == *=- ]] && stdin=yes
done

# First line is the token; stdin follows only when bao will read it (`-`, `k=-`).
{
  printf '%s\n' "$token"
  [ "$stdin" = no ] || cat
} | remote "IFS= read -r t; export BAO_ADDR=$addr BAO_TOKEN=\$t; $cmd"
