#!/usr/bin/env bash
# On the galaxy box: stream a tar.gz of the data that can't be rebuilt to stdout. Nothing is
# kept here; schematics' authorized_keys entry forces this script, and it keeps the only copy.
#   augur.dump    augur DB minus the sentinel archive, which is rescrapeable
#   globals.sql   atlas roles
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

kc exec atlas-0 -- pg_dump -U postgres -Fc --exclude-table-data=imagery_finder_archiveitem augur \
  > "$work/augur.dump"
kc exec atlas-0 -- pg_dumpall -U postgres --globals-only > "$work/globals.sql"

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
