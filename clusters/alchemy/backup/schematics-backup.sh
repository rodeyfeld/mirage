#!/usr/bin/env bash
# Nightly on the schematics box: full `forgejo dump` (repos, packages, LFS, DB, config)
# to /data/schematics/backups, keeping only the latest. galaxy pulls `latest.tar.gz` afterwards.
set -euo pipefail
umask 077

dir=/data/schematics/backups
mkdir -p "$dir"
out="$dir/schematics-$(date -u +%Y%m%dT%H%M%SZ).tar.gz"

k3s kubectl -n schematics exec deploy/schematics -- \
  forgejo dump --type tar.gz --file - --tempdir /tmp --quiet > "$out.part"
mv "$out.part" "$out"
ln -sfn "$(basename "$out")" "$dir/latest.tar.gz"
ls -1t "$dir"/schematics-*.tar.gz | tail -n +2 | xargs -r rm --
echo "✓ $(du -h "$out" | cut -f1) $out"
