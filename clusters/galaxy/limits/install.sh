#!/usr/bin/env bash
# Run from your machine (needs the `galaxy` ssh alias). Phase 6: priority classes, a
# namespace default limit, and requests/limits on every galaxy workload except cuneiform
# (a restart seals it). Applies them in an order where each app restarts once:
# stateless apps, then databases, then garage/doppler/atlas, then ouroboros last because
# restarting it kills any running pipeline. Each restart is a few seconds of downtime for
# that app; noctis-postgres is OnDelete and picks its limits up on its next restart.
# Safe to rerun; unchanged objects don't restart.
set -euo pipefail
cd "$(dirname "$0")/../../.."

kc() { ssh galaxy "k3s kubectl -n galaxy $*"; }
apply() {
  echo "→ $1"
  ssh galaxy 'k3s kubectl apply -f -' < "$1" | sed 's/^/  /'
}
wait_for() { kc rollout status "$1" --timeout=300s | tail -1 | sed 's/^/  /'; }

# Pods referencing a priority class are rejected until it exists, so these go first
apply cluster/scheduling/priority-classes.yml
apply cluster/scheduling/limitrange-galaxy.yml

for app in luna augur parakeet mycelia; do
  apply "apps/$app/deployment.yml"; wait_for "deployment/$app"
done
apply apps/parakeet/statefulset.yml; wait_for statefulset/parakeet-postgres
apply apps/mycelia/statefulset.yml; wait_for statefulset/mycelia-postgres
apply apps/noctis/noctis-postgres.yml
apply apps/noctis/prefect-server.yml; wait_for deployment/noctis-prefect-server
apply apps/noctis/deployment.yml; wait_for deployment/noctis
apply apps/garage/statefulset.yml; wait_for statefulset/garage
apply apps/doppler/deployment.yml; wait_for deployment/doppler
apply apps/atlas/statefulset.yml; wait_for statefulset/atlas
apply apps/ouroboros/ouroboros-server.yml; wait_for deployment/ouroboros-server
apply apps/ouroboros/ouroboros-agent.yml; wait_for deployment/ouroboros-agent

echo "→ result"
kc get pods -o 'custom-columns=POD:.metadata.name,STATUS:.status.phase,PRIORITY:.spec.priority,MEM_REQ:.spec.containers[0].resources.requests.memory,MEM_LIMIT:.spec.containers[0].resources.limits.memory' \
  | grep -v '^wp-' | sed 's/^/  /'

# A noctis restart ends a running sentinel-backfill; resume it from where the archive
# reaches (one window of overlap, which inserts skip)
resume=$(ssh galaxy "k3s kubectl -n galaxy exec ephemeris-0 -- psql -U postgres -d ephemeris -At -c \
  \"select (min(start_date) + interval '7 days')::date from imagery_finder_archiveitem\"")
echo
echo "If sentinel-backfill was running it was interrupted; resume it with:"
echo "  ssh galaxy \"k3s kubectl -n galaxy exec deploy/noctis -- prefect deployment run sentinel-backfill/manual --param before=$resume\""
