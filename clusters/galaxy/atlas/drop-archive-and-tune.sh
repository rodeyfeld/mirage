#!/usr/bin/env bash
# Run from your machine (needs the `galaxy` ssh alias). Phase 5 of the archive split:
#   1. checks ephemeris has the archive and nothing still reads atlas's old copy
#   2. drops imagery_finder_archiveitem from atlas (asks first; ~11 GB, rescrapeable),
#      after clearing the 323 old lookup items' links to it, as on_delete=SET_NULL would
#   3. rolls atlas onto apps/atlas/statefulset.yml: image pinned by digest, Postgres tuned,
#      2Gi memory limit (augur is down for the ~20s restart)
# Touches only atlas's augur database; doppler's SQLite and garage are elsewhere.
set -euo pipefail
cd "$(dirname "$0")/../../.."

atlas() { ssh -n galaxy "k3s kubectl -n galaxy exec atlas-0 -- psql -U postgres -d augur -v ON_ERROR_STOP=1 -At $*"; }
# SQL on stdin
atlas_sql() { ssh galaxy "k3s kubectl -n galaxy exec -i atlas-0 -- psql -U postgres -d augur -v ON_ERROR_STOP=1 -At"; }
ephemeris() { ssh -n galaxy "k3s kubectl -n galaxy exec ephemeris-0 -- psql -U postgres -d ephemeris -At $*"; }

echo "→ ephemeris has the archive?"
rows=$(ephemeris -c "'select count(*) from imagery_finder_archiveitem'")
echo "  $rows rows in ephemeris"
[ "$rows" -gt 0 ] || { echo "  ephemeris is empty; is the cutover done?" >&2; exit 1; }

if atlas -c "'select to_regclass(\$\$imagery_finder_archiveitem\$\$) is not null'" | grep -q t; then
  echo "→ atlas's old archive table"
  scans() { atlas -c "'select seq_scan + coalesce(idx_scan, 0) from pg_stat_user_tables where relname = \$\$imagery_finder_archiveitem\$\$'"; }
  before=$(scans); sleep 30; after=$(scans)
  atlas -c "'select n_live_tup || \$\$ rows, \$\$ || pg_size_pretty(pg_total_relation_size(relid)) from pg_stat_user_tables where relname = \$\$imagery_finder_archiveitem\$\$'" | sed 's/^/  /'
  if [ "$before" != "$after" ]; then
    echo "  something read it in the last 30s ($before -> $after scans); find it before dropping" >&2
    exit 1
  fi
  echo "  no reads in 30s"

  read -r -p "  Drop it? This can't be undone. Type DROP: " answer
  [ "$answer" = DROP ] || { echo "  not dropped"; exit 1; }
  atlas_sql <<'SQL'
BEGIN;
SET LOCAL lock_timeout = '5s';
UPDATE imagery_finder_archivelookupitem SET archive_item_id = NULL WHERE archive_item_id IS NOT NULL;
DROP TABLE imagery_finder_archiveitem;
COMMIT;
SQL
  echo "  dropped; augur db now $(atlas -c "'select pg_size_pretty(pg_database_size(current_database()))'")"
else
  echo "→ atlas's old archive table is already gone"
fi

echo "→ atlas: pinned image, tuning, limits"
ssh galaxy 'k3s kubectl apply -f -' < apps/atlas/statefulset.yml
ssh galaxy 'k3s kubectl -n galaxy rollout status statefulset/atlas --timeout=300s'
atlas -c "'select \$\$shared_buffers \$\$ || current_setting(\$\$shared_buffers\$\$) || \$\$, postgis \$\$ || extversion from pg_extension where extname = \$\$postgis\$\$'" | sed 's/^/  /'
ssh galaxy 'k3s kubectl -n galaxy get pod atlas-0 -o jsonpath="  limits {.spec.containers[0].resources.limits}, image {.status.containerStatuses[0].imageID}{\"\n\"}"; echo "  root disk: $(df -h / | awk "NR==2{print \$3\" used, \"\$4\" free\"}")"'

echo "→ augur"
for i in $(seq 20); do
  code=$(curl -s -o /dev/null -w '%{http_code}' https://luna.pinwheel.fan/api/providers/archive/freshness)
  [ "$code" = 200 ] && break; sleep 3
done
echo "  freshness via luna: $code"
