#!/usr/bin/env bash
# Restart only the galaxy workloads this push affects: the Deployments/StatefulSets
# declared under each apps/<app>/ that the push touched, plus apps whose Secret the
# sync-secrets step changed. A manual run (no changed-file list) restarts everything,
# as every push used to.
#   cuneiform: never restarted; a restart seals the vault
#   ouroboros: never restarted; it would kill this pipeline. Restart it by hand.
# Needs CI_PIPELINE_FILES (Woodpecker's JSON list of changed files) and kubectl.
set -uo pipefail
NS=galaxy
cd "$(dirname "$0")/.."

# namespace kind/name of each Deployment and StatefulSet in an app's manifests
workloads() {
  awk -v ns="$NS" '
    /^---/                       { kind = ""; meta = 0; name = ""; space = ns }
    /^kind:/                     { kind = $2 }
    /^metadata:/                 { meta = 1; next }
    /^[^ #]/                     { if (meta && name != "" && (kind == "Deployment" || kind == "StatefulSet")) print space " " tolower(kind) "/" name; meta = 0; name = "" }
    meta && /^  name:/           { name = $2 }
    meta && /^  namespace:/      { space = $2 }
    END                          { if (meta && name != "" && (kind == "Deployment" || kind == "StatefulSet")) print space " " tolower(kind) "/" name }
  ' apps/"$1"/*.yml | sort -u
}

if [ -z "${CI_PIPELINE_FILES:-}" ]; then
  echo "No changed-file list (manual run): restarting every app"
  apps=$(ls apps)
else
  apps=$( { printf '%s' "$CI_PIPELINE_FILES" | grep -oE '"apps/[^/"]+/' | cut -d/ -f2
            cat "${CHANGED_SECRETS_FILE:-/dev/null}" 2>/dev/null; } | sort -u)
fi

[ -n "$apps" ] || { echo "No app manifests or Secrets changed; nothing to restart"; exit 0; }

for app in $apps; do
  case "$app" in
    cuneiform) echo "skip cuneiform (would seal the vault)"; continue ;;
    ouroboros) echo "skip ouroboros (would kill this pipeline); restart it by hand"; continue ;;
  esac
  [ -d "apps/$app" ] || continue
  workloads "$app" | while read -r space w; do
    echo "Restarting $w ($app, namespace $space)"
    kubectl rollout restart -n "$space" "$w" || echo "  ! $w not restarted (not deployed yet?)"
  done
done
echo "Restart requests sent"
