# workers

The worker box: a single-node k3s in Europe (fsn1 or nbg1) for what nobody waits on,
away from galaxy's services. See diagrams/universe-plan.md in the workspace. Today it's
ready for the owner's spores; Woodpecker's agents, builds and sporocarps move here next.

mycelia starts the owner's ordinary spores here once `MYCELIA_WORKERS_API_URL`,
`MYCELIA_WORKERS_CA_PEM` and `MYCELIA_WORKERS_TOKEN` are set (`Spores.Host.Kube.workers/0`).
Mycologists, and spores whose home is still on galaxy, stay on galaxy. Colony spores
are unaffected: they run on their colony's server, or galaxy.

## Setting it up

```bash
# on the box (WORKERS_IP = its public IPv4)
cat > /etc/rancher/k3s/registries.yaml <<YAML      # so k3s can pull the spore image
configs:
  "schematics.pinwheel.fan":
    auth: { username: <registry user>, password: <read-only registry token> }
YAML
chmod 600 /etc/rancher/k3s/registries.yaml
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.36.5+k3s1 \
  INSTALL_K3S_EXEC="--secrets-encryption --tls-san $WORKERS_IP --disable traefik" sh -

# from mirage/
sed "s/WORKERS_IP/$WORKERS_IP/" clusters/workers/base.yml | ssh workers 'k3s kubectl apply -f -'

# mycelia's way in: into cuneiform as galaxy-kv/prod/mycelia (apps/mycelia/secrets.yml)
#   MYCELIA_WORKERS_API_URL  https://$WORKERS_IP:6443
#   MYCELIA_WORKERS_CA_PEM   /var/lib/rancher/k3s/server/tls/server-ca.crt
#   MYCELIA_WORKERS_TOKEN    k3s kubectl -n mycelia get secret control-plane-token -o jsonpath='{.data.token}' | base64 -d
```

A Hetzner firewall on the box: 6443 only from galaxy (5.161.236.179), 22 from the owner.
Nothing else needs to come in: spores are reached through the API server's pod proxy.
