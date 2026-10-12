#!/usr/bin/env bash
# Run from your machine (needs the `galaxy` ssh alias). Caps what can fill galaxy's root disk
# and adds kubelet eviction/reservation limits: prunes unused images, caps the journal at 1G,
# installs k3s-config.yaml and restarts k3s if it changed (running containers keep running;
# the API is down ~30s). Safe to rerun.
set -euo pipefail
cd "$(dirname "$0")"

put() {
  ssh "$1" "tmp=\$(mktemp) && cat > \$tmp && install -D -m $2 \$tmp $3 && rm -f \$tmp"
}

echo "→ before: $(ssh galaxy 'df -h / | tail -1')"

echo "→ prune unused images"
# crictl's default 2s timeout trips on big layer deletions; containerd finishes them regardless
ssh galaxy 'k3s crictl --timeout 5m rmi --prune 2>&1 | grep -c "^Deleted" || true'

echo "→ cap the journal at 1G"
put galaxy 644 /etc/systemd/journald.conf.d/size.conf < journald-size.conf
ssh galaxy 'systemctl restart systemd-journald && journalctl --vacuum-size=1G 2>&1 | tail -1'

echo "→ kubelet limits"
if ssh galaxy 'cat /etc/rancher/k3s/config.yaml 2>/dev/null' | cmp -s - k3s-config.yaml; then
  echo "  unchanged, no restart"
else
  put galaxy 600 /etc/rancher/k3s/config.yaml < k3s-config.yaml
  echo "  restarting k3s"
  ssh galaxy 'systemctl restart k3s'
  ssh galaxy 'for i in $(seq 60); do k3s kubectl get node --no-headers 2>/dev/null | grep -qw Ready && exit 0; sleep 2; done; echo "node not Ready after 120s" >&2; exit 1'
fi

echo "→ after: $(ssh galaxy 'df -h / | tail -1')"
# The kubelet takes a few seconds after Ready to publish the reduced allocatable
sleep 15
ssh galaxy 'echo "  allocatable: $(k3s kubectl get node -o jsonpath="{.items[0].status.allocatable.cpu} cpu, {.items[0].status.allocatable.memory}")"; k3s kubectl -n galaxy get pods --no-headers | grep -vE "Running|Completed" || echo "  all pods Running"'
