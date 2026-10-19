#!/usr/bin/env bash
# Creates schematics-env-secrets with generated values if it doesn't exist yet.
# Never overwrites. Run on the schematics box: `ssh schematics 'bash -s' < bootstrap-secrets.sh`
# (Moves to an apps/schematics/secrets.yml once cuneiform lives on this cluster.)
set -euo pipefail

kubectl() { k3s kubectl "$@"; }
b64url() { openssl rand -base64 32 | tr '+/' '-_' | tr -d '='; }

if kubectl -n schematics get secret schematics-env-secrets >/dev/null 2>&1; then
  echo "✓ schematics-env-secrets already exists, leaving it alone"
  exit 0
fi

pg_password=$(openssl rand -hex 24)
kubectl -n schematics create secret generic schematics-env-secrets \
  --from-literal=POSTGRES_PASSWORD="$pg_password" \
  --from-literal=FORGEJO__database__PASSWD="$pg_password" \
  --from-literal=FORGEJO__security__SECRET_KEY="$(openssl rand -hex 32)" \
  --from-literal=FORGEJO__security__INTERNAL_TOKEN="$(openssl rand -hex 48)" \
  --from-literal=FORGEJO__oauth2__JWT_SECRET="$(b64url)" \
  --from-literal=FORGEJO__server__LFS_JWT_SECRET="$(b64url)"
echo "✓ schematics-env-secrets created"
