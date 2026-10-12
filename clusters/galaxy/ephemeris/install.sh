#!/usr/bin/env bash
# Run from your machine (needs the `galaxy` ssh alias). Prepares galaxy for ephemeris, the
# archive Postgres on Hetzner volume volume-ash-1: makes its data directory on the volume
# and applies the cluster-scoped pieces CI can't (PriorityClass, PV, ServiceAccount).
# Then push mirage; CI generates the password, creates the PVC/StatefulSet/Service and
# starts it. Rerun this afterwards to check it came up on the volume. Safe to rerun.
set -euo pipefail
cd "$(dirname "$0")/../../.."
vol=/mnt/HC_Volume_107107523

apply() { ssh galaxy 'k3s kubectl apply -f -' < "$1"; }

echo "→ volume mounted at $vol?"
ssh galaxy "mountpoint -q $vol && df -h $vol | tail -1" || {
  echo "  volume-ash-1 isn't mounted; attach it in the Hetzner console and mount it first" >&2
  exit 1
}

echo "→ data directory on the volume"
ssh galaxy "install -d -m 700 $vol/ephemeris && ls -ld $vol/ephemeris"

echo "→ cluster-scoped objects"
apply cluster/scheduling/priority-classes.yml
apply apps/ephemeris/serviceaccount.yml
apply apps/ephemeris/pv.yml

if ! ssh galaxy 'k3s kubectl -n galaxy get pod ephemeris-0' >/dev/null 2>&1; then
  echo
  echo "Ready. Push mirage; CI creates the rest and restarts only ephemeris."
  echo "Then rerun this script to check it."
  exit 0
fi

echo "→ ephemeris status"
ssh galaxy 'k3s kubectl -n galaxy wait --for=condition=Ready pod/ephemeris-0 --timeout=180s'
ssh galaxy "k3s kubectl -n galaxy exec ephemeris-0 -- psql -U postgres -d ephemeris -Atc \
  \"select 'postgis ' || extversion from pg_extension where extname = 'postgis'\" &&
  k3s kubectl -n galaxy get pod ephemeris-0 -o jsonpath='  priority {.spec.priority}, limits {.spec.containers[0].resources.limits}{\"\\n\"}' &&
  echo \"  on volume: \$(du -sh $vol/ephemeris | cut -f1), root disk: \$(df -h / | awk 'NR==2{print \$3\" used\"}')\""
