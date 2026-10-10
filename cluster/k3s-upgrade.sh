#!/usr/bin/env bash
# Upgrade the single-node k3s server on galaxy to a given release, one minor at a time.
# Replaces the binary in place (keeps the systemd unit untouched), after backing up server state.
#
# Usage: ./cluster/k3s-upgrade.sh v1.34.12+k3s1
set -euo pipefail

VERSION="${1:?usage: $0 <k3s version, e.g. v1.34.12+k3s1>}"
HOST="${K3S_HOST:-galaxy}"

ssh "$HOST" VERSION="$VERSION" bash -s <<'REMOTE'
set -euo pipefail
TAG="${VERSION//+/%2B}"
BASE="https://github.com/k3s-io/k3s/releases/download/$TAG"
CURRENT="$(k3s --version | awk 'NR==1{print $3}')"
echo "current: $CURRENT  target: $VERSION"

TMP="$(mktemp -d)"
curl -sSfL -o "$TMP/k3s" "$BASE/k3s"
curl -sSfL -o "$TMP/sha256sum-amd64.txt" "$BASE/sha256sum-amd64.txt"
(cd "$TMP" && grep ' k3s$' sha256sum-amd64.txt | sha256sum -c -)

# Stop k3s so the sqlite datastore is consistent on disk; pods keep running via containerd shims
systemctl stop k3s
BACKUP="/root/k3s-backup-$(date +%Y%m%d-%H%M%S)-$CURRENT.tgz"
tar -czf "$BACKUP" -C /var/lib/rancher/k3s/server db token tls cred
cp /usr/local/bin/k3s "/root/k3s-$CURRENT.bin"
echo "backup: $BACKUP (old binary: /root/k3s-$CURRENT.bin)"

install -m 755 "$TMP/k3s" /usr/local/bin/k3s
rm -rf "$TMP"
systemctl start k3s

echo "waiting for node Ready on $VERSION..."
for _ in $(seq 60); do
  if k3s kubectl get nodes --no-headers 2>/dev/null | grep -q " Ready .*${VERSION}"; then break; fi
  sleep 5
done
k3s kubectl get nodes -o wide
sleep 30  # give helm-controller time to replace the old completed traefik job
k3s kubectl -n kube-system wait --for=condition=complete job/helm-install-traefik --timeout=300s || true
k3s kubectl -n kube-system get deploy traefik -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
echo "pods not running:"
k3s kubectl get pods -A --no-headers | grep -v -E 'Running|Completed' || echo "  none"
REMOTE
