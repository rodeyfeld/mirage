#!/usr/bin/env bash
# Nightly on the galaxy box: copy schematics' latest dump to /data/backups/schematics, keeping only it.
# The key only works for this: schematics' authorized_keys forces `cat latest.tar.gz`.
set -euo pipefail
umask 077

dir=/data/backups/schematics
mkdir -p "$dir"
out="$dir/schematics.tar.gz"

ssh -i /root/.ssh/schematics-backup -p 2222 -o BatchMode=yes root@schematics.pinwheel.fan > "$out.part"
gzip -t "$out.part"
mv "$out.part" "$out"
# Dated copies from when this kept 14
rm -f "$dir"/schematics-*.tar.gz
echo "✓ $(du -h "$out" | cut -f1) $out"
