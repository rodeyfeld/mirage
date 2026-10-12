#!/usr/bin/env bash
# sync.sh — make cuneiform (OpenBao) and the galaxy namespace match this repo.
#
#   1. Policies: every cuneiform-policies/<app>-policy.hcl is written as
#      `<app>-policy`, plus a Kubernetes auth role `<app>` binding it to the
#      `<app>` ServiceAccount in galaxy. (Replaces running apply-policies.sh.)
#   2. Secrets: every apps/<app>/secrets.yml is read:
#        path:      KV v2 path in cuneiform (galaxy-kv/prod/<app>)
#        secret:    the k8s Secret to write in galaxy
#        generate:  keys to create once if missing (alnum-N | base64-N | hex-N);
#                   an existing value is never overwritten
#        env:       Secret key -> template; `{key}` reads this app's path,
#                   `{other.key}` reads galaxy-kv/prod/other
#      and the k8s Secret is rebuilt from `env`.
#
# Usage (from the mirage root): cuneiform-policies/sync.sh [check|apply]
#   check  read-only: reports what would change, by key NAME only (never values)
#   apply  writes policies/roles, generates missing keys, applies the Secrets
# Needs BAO_ADDR + BAO_TOKEN, curl, jq, yq (v4), kubectl.
set -uo pipefail

MODE="${1:-apply}"
case "$MODE" in check|apply) ;; *) echo "usage: $0 [check|apply]" >&2; exit 2 ;; esac
NS=galaxy
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failed=()

# ---- OpenBao HTTP API --------------------------------------------------------
# bao METHOD PATH [JSON] -> body in $TMP/body, echoes the HTTP status.
bao() {
  local args=(-sS -o "$TMP/body" -w '%{http_code}' -X "$1" -H "X-Vault-Token: $BAO_TOKEN")
  # KV v2 PATCH (adding keys to an existing path) is a JSON merge patch; any
  # other content type, or a second content-type header, gets a 415.
  local ctype='content-type: application/json'
  [ "$1" = PATCH ] && ctype='content-type: application/merge-patch+json'
  [ -n "${3:-}" ] && args+=(-H "$ctype" --data-binary "$3")
  curl "${args[@]}" "$BAO_ADDR/v1/$2" || echo 000
}

# KV v2 "mount/rest" -> API data path "mount/data/rest".
kv_api() { echo "${1%%/*}/data/${1#*/}"; }

# Read a KV path's data into $TMP/kv.json. Returns 0 found, 1 missing, 2 error.
kv_read() {
  local code; code="$(bao GET "$(kv_api "$1")")"
  case "$code" in
    200) jq -c '.data.data // {}' "$TMP/body" > "$TMP/kv.json"; return 0 ;;
    404) echo '{}' > "$TMP/kv.json"; return 1 ;;
    *) echo "  ! read $1 failed (HTTP $code)"; return 2 ;;
  esac
}

gen() {
  local kind="${1%-*}" n="${1##*-}"
  case "$kind" in
    alnum) head -c 512 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c "$n" ;;
    base64) head -c "$n" /dev/urandom | base64 | tr -d '\n' ;;
    hex) head -c "$n" /dev/urandom | od -An -tx1 | tr -d ' \n' ;;
    *) return 1 ;;
  esac
}

# A sealed vault answers 503 to everything; stop with the fix instead.
if [ "$(bao GET sys/seal-status)" != 200 ] || jq -e '.sealed' "$TMP/body" >/dev/null; then
  echo "cuneiform at $BAO_ADDR is sealed or unreachable; unseal it (bao operator unseal x3) and rerun"
  exit 1
fi

# ---- 1. policies + roles -----------------------------------------------------
echo "== policies"
probe='{"paths":["sys/policies/acl/probe","auth/kubernetes/role/probe"]}'
if [ "$(bao POST sys/capabilities-self "$probe")" = 200 ]; then
  pol_caps="$(jq -r '(.data // .)["sys/policies/acl/probe"] // [] | join(",")' "$TMP/body")"
  role_caps="$(jq -r '(.data // .)["auth/kubernetes/role/probe"] // [] | join(",")' "$TMP/body")"
else
  pol_caps=deny role_caps=deny
fi
can() { [[ ",$1," == *,root,* || ",$1," == *,update,* || ",$1," == *,create,* ]]; }
k8s_auth=no
[ "$(bao GET sys/auth)" = 200 ] && jq -e '.data["kubernetes/"] // ."kubernetes/"' "$TMP/body" >/dev/null && k8s_auth=yes

if ! can "$pol_caps"; then
  echo "  ! token can't write policies (capabilities: $pol_caps); skipping policies + roles"
else
  for hcl in cuneiform-policies/*-policy.hcl; do
    name="$(basename "$hcl" .hcl)"; app="${name%-policy}"
    want="$(cat "$hcl")"
    have=""; [ "$(bao GET "sys/policies/acl/$name")" = 200 ] && have="$(jq -r '.data.policy // .policy' "$TMP/body")"
    if [ "$have" = "$want" ]; then pstate=same; elif [ -z "$have" ]; then pstate=new; else pstate=changed; fi

    role_body="$(jq -nc --arg sa "$app" --arg p "$name" \
      '{bound_service_account_names:[$sa], bound_service_account_namespaces:["galaxy"], policies:[$p], ttl:"24h"}')"
    rstate=skipped
    if [ "$k8s_auth" = yes ] && can "$role_caps"; then
      if [ "$(bao GET "auth/kubernetes/role/$app")" = 200 ] &&
         jq -e --arg sa "$app" --arg p "$name" \
           '.data.bound_service_account_names == [$sa] and (.data.token_policies // .data.policies) == [$p]' \
           "$TMP/body" >/dev/null; then rstate=same; else rstate=new-or-changed; fi
    fi
    echo "  $app: policy $pstate, role $rstate"

    if [ "$MODE" = apply ]; then
      if [ "$pstate" != same ]; then
        code="$(bao PUT "sys/policies/acl/$name" "$(jq -nc --arg p "$want" '{policy:$p}')")"
        [[ "$code" == 20* ]] || { echo "  ! write policy $name failed (HTTP $code)"; failed+=("policy:$app"); }
      fi
      if [ "$rstate" = new-or-changed ]; then
        code="$(bao POST "auth/kubernetes/role/$app" "$role_body")"
        [[ "$code" == 20* ]] || { echo "  ! write role $app failed (HTTP $code)"; failed+=("role:$app"); }
      fi
    fi
  done
  [ "$k8s_auth" = yes ] || echo "  ! kubernetes auth method not enabled; roles skipped"
fi

# ---- 2. secrets --------------------------------------------------------------
echo "== secrets"
for spec in apps/*/secrets.yml; do
  app="$(basename "$(dirname "$spec")")"
  yq -o=json '.' "$spec" > "$TMP/spec.json"
  path="$(jq -r '.path' "$TMP/spec.json")"
  secret="$(jq -r '.secret' "$TMP/spec.json")"
  prefix="${path%/*}"
  echo "  $app -> $secret ($path)"

  kv_read "$path"; found=$?
  [ "$found" = 2 ] && { failed+=("$app"); continue; }
  cp "$TMP/kv.json" "$TMP/own.json"

  # Generate declared keys that are missing — never touching existing ones.
  missing="$(jq -r --slurpfile have "$TMP/own.json" \
    '(.generate // {}) | to_entries[] | select($have[0][.key] == null) | "\(.key) \(.value)"' "$TMP/spec.json")"
  if [ -n "$missing" ]; then
    echo '{}' > "$TMP/new.json"
    bad=no
    while read -r key kind; do
      val="$(gen "$kind")" || { echo "    ! unknown generator '$kind' for $key"; bad=yes; continue; }
      [ "$MODE" = check ] && val="<generated>"
      jq -c --arg k "$key" --arg v "$val" '. + {($k): $v}' "$TMP/new.json" > "$TMP/n" && mv "$TMP/n" "$TMP/new.json"
      echo "    generate $key ($kind)"
    done <<< "$missing"
    [ "$bad" = yes ] && { failed+=("$app"); continue; }

    if [ "$MODE" = apply ]; then
      if [ "$found" = 1 ]; then  # new path: cas=0 refuses to overwrite one that appeared meanwhile
        code="$(bao POST "$(kv_api "$path")" "$(jq -c '{options:{cas:0}, data:.}' "$TMP/new.json")")"
      else
        code="$(bao PATCH "$(kv_api "$path")" "$(jq -c '{data:.}' "$TMP/new.json")")"
      fi
      [[ "$code" == 20* ]] || { echo "    ! write $path failed (HTTP $code)"; failed+=("$app"); continue; }
    fi
    jq -c --slurpfile n "$TMP/new.json" '. + $n[0]' "$TMP/own.json" > "$TMP/o" && mv "$TMP/o" "$TMP/own.json"
  fi

  # Values available to templates: own keys, plus `other.key` from referenced paths.
  cp "$TMP/own.json" "$TMP/vals.json"
  for other in $(jq -r '.env[]' "$TMP/spec.json" | grep -oE '\{[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\}' | sed -E 's/^\{([^.]+)\..*/\1/' | sort -u); do
    kv_read "$prefix/$other"
    jq -c --slurpfile o "$TMP/kv.json" --arg a "$other" \
      '. + ($o[0] | with_entries(.key = "\($a).\(.key)"))' "$TMP/vals.json" > "$TMP/v" && mv "$TMP/v" "$TMP/vals.json"
  done

  # Render. A reference with no value fails this app rather than writing "null".
  jq -c --slurpfile v "$TMP/vals.json" \
    '.env | map_values(gsub("\\{(?<r>[A-Za-z0-9_.-]+)\\}"; ($v[0][.r] // "@@MISSING:\(.r)@@") | tostring))' \
    "$TMP/spec.json" > "$TMP/env.json"
  unresolved="$(jq -r '[.[] | scan("@@MISSING:([^@]+)@@") | .[0]] | unique | join(", ")' "$TMP/env.json")"
  if [ -n "$unresolved" ]; then
    echo "    ! no value in cuneiform for: $unresolved — leaving $secret untouched"
    failed+=("$app"); continue
  fi

  # Diff against the live Secret by key name only.
  kubectl get secret "$secret" -n "$NS" -o json 2>/dev/null | jq -c '.data // {}' > "$TMP/live.json" || echo '{}' > "$TMP/live.json"
  [ -s "$TMP/live.json" ] || echo '{}' > "$TMP/live.json"
  jq -r --slurpfile live "$TMP/live.json" '
    (map_values(@base64)) as $want | $live[0] as $have |
    ([$want | keys[] | select($have[.] == null)] | if length > 0 then "    new keys: \(join(", "))" else empty end),
    ([$want | keys[] | select($have[.] != null and $have[.] != $want[.])] | if length > 0 then "    changed: \(join(", "))" else empty end),
    ([$have | keys[] | select($want[.] == null)] | if length > 0 then "    removed: \(join(", "))" else empty end),
    (if ($want == $have) then "    unchanged" else empty end)
  ' "$TMP/env.json"

  if [ "$MODE" = apply ]; then
    jq -c --arg n "$secret" --arg ns "$NS" \
      '{apiVersion:"v1", kind:"Secret", type:"Opaque", metadata:{name:$n, namespace:$ns}, data:map_values(@base64)}' \
      "$TMP/env.json" | kubectl apply -f - >/dev/null || { echo "    ! kubectl apply $secret failed"; failed+=("$app"); }
    # Tell the restart step which apps need new pods to pick up their Secret
    if [ -n "${CHANGED_SECRETS_FILE:-}" ] &&
       ! jq -e --slurpfile live "$TMP/live.json" 'map_values(@base64) == $live[0]' "$TMP/env.json" >/dev/null; then
      echo "$app" >> "$CHANGED_SECRETS_FILE"
    fi
  fi
done

if [ "${#failed[@]}" -gt 0 ]; then
  echo "FAILED: ${failed[*]}"
  exit 1
fi
echo "OK ($MODE)"
