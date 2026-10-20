# Mirage

All the k8s manifests for the galaxy cluster running on Hetzner.

Each app is `apps/<app>/`: its `deployment.yml`, `service.yml`, `configmap.yml`, `ingress.yml`,
storage (`*pv.yml`/`*pvc.yml`), RBAC and `secrets.yml` (what cuneiform syncs into its
Secret). Clusters other than galaxy, and galaxy's host setup, are in `clusters/`:
`clusters/galaxy/` (k3s config, limits, backups), `clusters/alchemy/` (the forge's box,
schematics) and `clusters/workers/` (the worker box, for spores).

## Deploying

Pushing to `main` deploys, through `.woodpecker.yml` on ouroboros:

1. `sync-secrets` makes cuneiform and each app's Secret match `apps/*/secrets.yml`
   (`cuneiform-policies/`).
2. `apply-all` applies the namespace-scoped manifests: `deployment.yml`, `*-postgres.yml`,
   `service.yml`, `configmap.yml`, `statefulset.yml`, `*pvc.yml`, `job.yml`.
3. `restart-changed` restarts the apps this push touched (`ci/restart-changed.sh`).

Everything else is applied by hand: namespaces, RBAC, PVs, ingresses, NetworkPolicies,
quotas, and files the pipeline's globs don't match (e.g. `apps/ouroboros/ouroboros-*.yml`,
`apps/garage/garage*.yml`, `apps/noctis/prefect-server.yml`, `apps/augur/augur-db-migrate.yml`):

```bash
ssh galaxy 'k3s kubectl apply -f -' < apps/<app>/<file>.yml
```

Each project's own `.woodpecker.yml` builds its image into the schematics registry and
restarts its workload; `deploy-status <repo>` (in a spore) says how it went.

## Cluster components

Applied by hand, not by the pipeline:

- **cert-manager**: static manifest pinned in `cluster/cert-manager/cert-manager.yml`, no Helm. To upgrade, swap in the release's `cert-manager.yaml` (one minor at a time) and run:
  ```bash
  ssh galaxy 'k3s kubectl apply --server-side --force-conflicts -f -' < cluster/cert-manager/cert-manager.yml
  ```
- **k3s** (and the Traefik it bundles): `./cluster/k3s-upgrade.sh <version>`, one minor at a time. It backs up server state to `/root` before swapping the binary.
- **Routing**: `cluster/routing/middleware-https.yml` and `apps/*/ingress.yml`. Middlewares must use `traefik.io/v1alpha1`, because Traefik 3 ignores `traefik.containo.us`.
