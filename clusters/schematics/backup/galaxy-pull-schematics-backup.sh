#!/usr/bin/env bash
# Nightly on the galaxy box: copy schematics' latest dump to /data/backups/schematics, keeping 14.
# The key only works for this: schematics' authorized_keys forces `cat latest.tar.gz`.
set -euo pipefail
umask 077

dir=/data/backups/schematics
mkdir -p "$dir"
out="$dir/schematics-$(date -u +%Y%m%d).tar.gz"

ssh -i /root/.ssh/schematics-backup -p 2222 -o BatchMode=yes root@schematics.pinwheel.fan > "$out.part"
gzip -t "$out.part"
mv "$out.part" "$out"
ls -1t "$dir"/schematics-*.tar.gz | tail -n +15 | xargs -r rm --
echo "✓ $(du -h "$out" | cut -f1) $out"
