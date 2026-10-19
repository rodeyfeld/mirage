#!/usr/bin/env bash
# On the galaxy box: stream a tar.gz of the data that can't be rebuilt to stdout. Nothing is
# kept here; schematics' authorized_keys entry forces this script, and it keeps the only copy.
#   atlas/<db>.dump  every atlas DB (augur, petrichor, pothos, tempeh, …), augur minus the
#                    sentinel archive, which is rescrapeable
#   globals.sql   atlas roles
#   postgres/<app>.sql.gz  the apps' own Postgres: mycelia, parakeet, noctis (prefect), aqueduct
#   Not here: ephemeris (augur's satellite archive): it's re-pulled from Copernicus if lost.
#   doppler.db    doppler posts (SQLite online backup, safe while doppler runs)
#   garage/       node key, layouts, metadata snapshots + data blocks (doppler photos)
#   cuneiform/    OpenBao raft storage
set -euo pipefail
umask 077

# The tarball goes to the ssh channel on fd 3; everything else is log output on stderr
exec 3>&1 1>&2

kc() { k3s kubectl -n galaxy "$@"; }
pv_path() {
  kc get pv "$(kc get pvc "$1" -o jsonpath='{.spec.volumeName}')" \
    -o jsonpath='{.spec.hostPath.path}{.spec.local.path}'
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir "$work/atlas" "$work/postgres"
dbs=$(kc exec atlas-0 -- psql -U postgres -Atc \
  "SELECT datname FROM pg_database WHERE NOT datistemplate AND datname <> 'postgres'")
for db in $dbs; do
  skip=(); [ "$db" = augur ] && skip=(--exclude-table-data=imagery_finder_archiveitem)
  kc exec atlas-0 -- pg_dump -U postgres -Fc "${skip[@]}" "$db" > "$work/atlas/$db.dump"
done
kc exec atlas-0 -- pg_dumpall -U postgres --globals-only > "$work/globals.sql"

# Each app's own Postgres, as its own user (from the pod's env). One that fails is logged and
# left out rather than costing the whole night's backup.
pg_all() { # namespace pod name
  if k3s kubectl -n "$1" exec "$2" -- sh -c 'pg_dumpall -U "${POSTGRES_USER:-postgres}"' \
      | gzip > "$work/postgres/$3.sql.gz"; then :         # pipefail: a failed dump fails here
  else echo "! $3: dump failed, left out"; rm -f "$work/postgres/$3.sql.gz"; fi
}
pg_all galaxy mycelia-postgres-0 mycelia
pg_all galaxy parakeet-postgres-0 parakeet
pg_all galaxy noctis-postgres-0 noctis
pg_all haar aqueduct-postgres-0 aqueduct

sqlite3 "$(pv_path doppler-volume-claim)/doppler.db" ".backup '$work/doppler.db'"

garage_meta=$(pv_path garage-meta-pvc)
garage_data=$(pv_path garage-data-pvc)
cuneiform=$(pv_path cuneiform-pvc)

# The live LMDB isn't safe to copy; garage writes a consistent copy to meta/snapshots
kc exec garage-0 -- /garage meta snapshot

# Lay the sources out under $work via symlinks and let tar follow them
mkdir "$work/garage"
ln -s "$garage_meta" "$work/garage/meta"
ln -s "$garage_data" "$work/garage/data"
ln -s "$cuneiform" "$work/cuneiform"

tar --dereference --exclude=./garage/meta/db.lmdb -czf - -C "$work" . >&3

echo "✓ galaxy backup streamed"
