#!/usr/bin/env bash
# Nightly on the schematics box: pull galaxy's backup into /data/galaxy/backups/galaxy.tar.gz,
# keeping only the latest. The key only works for this: galaxy's authorized_keys forces
# `galaxy-backup.sh`, which streams the tarball.
set -euo pipefail
umask 077

dir=/data/galaxy/backups
mkdir -p "$dir"
out="$dir/galaxy.tar.gz"

ssh -i /root/.ssh/galaxy-backup -o BatchMode=yes root@pinwheel.fan > "$out.part"
gzip -t "$out.part"
mv "$out.part" "$out"
echo "✓ $(du -h "$out" | cut -f1) $out"
