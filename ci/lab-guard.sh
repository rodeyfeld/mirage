#!/bin/sh
# lab-guard.sh: the lab's apps (apps/lab-*/) stay in the lab. Runs first in mirage's
# pipeline, so nothing is synced or applied if it fails. the adept can push
# only apps/lab-*/** (mirage's branch protection); this checks what's in them, since
# CI applies them with a deployer that can write anywhere:
#
#   - every object is in the `lab` namespace, and of a kind the lab may have;
#   - a secrets spec syncs into `lab`, from galaxy-kv/prod/<its dir>, and uses only
#     its own keys (no `{otherapp.key}`, which would copy another app's secrets in).
#
# Pod security (the namespace is "restricted") stops hostPath and privileged pods on
# top of this. Needs yq.
set -eu

kinds="Deployment Service ConfigMap StatefulSet PersistentVolumeClaim Job Ingress"
fail=0
bad() { echo "lab-guard: $*" >&2; fail=1; }

for dir in apps/lab-*/; do
  [ -d "$dir" ] || continue
  app=$(basename "$dir")
  for file in "$dir"*.yml "$dir"*.yaml; do
    [ -f "$file" ] || continue
    if [ "$(basename "$file")" = secrets.yml ]; then
      path=$(yq -r '.path // ""' "$file")
      ns=$(yq -r '.namespace // ""' "$file")
      [ "$path" = "galaxy-kv/prod/$app" ] || bad "$file: path must be galaxy-kv/prod/$app (is '$path')"
      [ "$ns" = lab ] || bad "$file: namespace must be lab (is '$ns')"
      if yq -r '.env // {} | to_entries | .[].value' "$file" | grep -Eq '\{[^}]*\.[^}]*\}'; then
        bad "$file: env may only use this app's own keys, not {otherapp.key}"
      fi
      continue
    fi
    # One line per object: "<kind> <namespace>".
    problems=$(yq ea -r 'select(. != null) | (.kind // "?") + " " + (.metadata.namespace // "?")' "$file" |
      while read -r kind ns; do
        case " $kinds " in *" $kind "*) ;; *) echo "a $kind isn't allowed in the lab" ;; esac
        [ "$ns" = lab ] || echo "$kind is in namespace '$ns', not lab"
      done)
    [ -z "$problems" ] || bad "$file: $problems"
  done
done

[ "$fail" = 0 ] && echo "lab-guard: every lab app stays in the lab" || exit 1
