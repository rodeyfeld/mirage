#!/usr/bin/env bash
# Run from your machine (needs the `galaxy` and `schematics` ssh aliases). Sets up the nightly
# galaxy → schematics backup, cuts the existing schematics → galaxy backup to one copy, and
# runs the first pull. Safe to rerun.
set -euo pipefail
cd "$(dirname "$0")"
schematics_backup=../../schematics/backup

# put HOST MODE DEST < file. Via a temp file: schematics' uutils `install` can't read
# /dev/stdin when DEST already exists
put() {
  ssh "$1" "tmp=\$(mktemp) && cat > \$tmp && install -m $2 \$tmp $3 && rm -f \$tmp"
}

echo "→ galaxy: backup script"
put galaxy 700 /usr/local/bin/galaxy-backup.sh < galaxy-backup.sh

echo "→ schematics: pull key + galaxy's host key"
ssh schematics 'test -f /root/.ssh/galaxy-backup || ssh-keygen -q -t ed25519 -N "" -C schematics-pull-galaxy-backup -f /root/.ssh/galaxy-backup'
hostkey=$(ssh galaxy 'cut -d" " -f1,2 /etc/ssh/ssh_host_ed25519_key.pub')
ssh schematics "grep -qF 'pinwheel.fan $hostkey' /root/.ssh/known_hosts 2>/dev/null || echo 'pinwheel.fan $hostkey' >> /root/.ssh/known_hosts"

echo "→ galaxy: let that key run galaxy-backup.sh and nothing else"
pub=$(ssh schematics 'cat /root/.ssh/galaxy-backup.pub')
ssh galaxy "grep -qF '$pub' /root/.ssh/authorized_keys || echo 'restrict,command=\"/usr/local/bin/galaxy-backup.sh\" $pub' >> /root/.ssh/authorized_keys"

echo "→ schematics: nightly pull (07:00 UTC)"
put schematics 700 /usr/local/bin/schematics-pull-galaxy-backup.sh < schematics-pull-galaxy-backup.sh
for unit in service timer; do
  put schematics 644 /etc/systemd/system/schematics-pull-galaxy-backup.$unit \
    < "schematics-pull-galaxy-backup.$unit"
done
ssh schematics 'systemctl daemon-reload && systemctl enable --now schematics-pull-galaxy-backup.timer'

echo "→ one copy only for the forge backups"
put schematics 755 /usr/local/bin/schematics-backup.sh < "$schematics_backup/schematics-backup.sh"
put galaxy 700 /usr/local/bin/galaxy-pull-schematics-backup.sh < "$schematics_backup/galaxy-pull-schematics-backup.sh"

echo "→ first pull (~140 MB)"
ssh schematics 'systemctl start schematics-pull-galaxy-backup.service; journalctl -u schematics-pull-galaxy-backup -n 3 --no-pager -o cat'
