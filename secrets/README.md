# Kubernetes Secrets

This directory contains **template files** for Kubernetes secrets. **DO NOT commit actual secrets to git.**

## Structure

- `*.template.yml` - Template files (committed to git)
- `*.yml` - Actual secrets with real values (**gitignored**, create manually)

## Creating Secrets

### Method 1: From Template File

1. Copy template and fill in real values:

```bash
cd /home/prometheus/universe/mirage/secrets
cp doppler-secrets.template.yml doppler-secrets.yml
# Edit doppler-secrets.yml with real secrets
kubectl apply -f doppler-secrets.yml
```

2. Delete the file after applying (don't leave secrets on disk):

```bash
rm doppler-secrets.yml
```

### Method 2: Direct kubectl create (Recommended)

```bash
# Doppler secrets
kubectl create secret generic doppler-env-secrets \
  --from-literal=DOPPLER_SESSION_SECRET="$(openssl rand -base64 32)" \
  --from-literal=S3_ACCESS_KEY_ID="your-s3-key" \
  --from-literal=S3_SECRET_ACCESS_KEY="your-s3-secret" \
  -n galaxy

# Luna secrets
kubectl create secret generic luna-env-secrets \
  --from-literal=LUNA_AUGUR_HOST="http://augur-service.galaxy.svc.cluster.local:8000" \
  -n galaxy

# Augur secrets
kubectl create secret generic augur-env-secrets \
  --from-literal=AUGUR_SECRET_KEY="$(python -c 'from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())')" \
  --from-literal=AUGUR_DEBUG="False" \
  --from-literal=AUGUR_ALLOWED_HOSTS="augur.pinwheel.fan,augur-service,augur-service.galaxy.svc.cluster.local" \
  --from-literal=AUGUR_CORS_ALLOWED_ORIGINS="https://luna.pinwheel.fan" \
  --from-literal=AUGUR_DB_HOST="atlas-service.galaxy.svc.cluster.local" \
  --from-literal=AUGUR_DB_USER="your-db-user" \
  --from-literal=AUGUR_DB_PASSWORD="your-db-password" \
  --from-literal=AUGUR_DREAMFLOW_HOST="http://dreamflow-service.galaxy.svc.cluster.local:8080" \
  --from-literal=AUGUR_DREAMFLOW_USER="your-airflow-user" \
  --from-literal=AUGUR_DREAMFLOW_PASSWORD="your-airflow-password" \
  -n galaxy

# Atlas secrets
kubectl create secret generic atlas-env-secrets \
  --from-literal=POSTGRES_PASSWORD="your-postgres-password" \
  -n galaxy
```

## Updating Secrets

```bash
# Patch individual keys
kubectl patch secret doppler-env-secrets -n galaxy \
  --type='json' \
  -p='[{"op":"replace","path":"/data/DOPPLER_SESSION_SECRET","value":"'$(echo -n "new-secret" | base64)'"}]'

# Or delete and recreate
kubectl delete secret doppler-env-secrets -n galaxy
kubectl create secret generic doppler-env-secrets ... # (see above)
```

## Viewing Secrets

```bash
# List all secrets
kubectl get secrets -n galaxy

# View secret (base64 encoded)
kubectl get secret doppler-env-secrets -n galaxy -o yaml

# Decode specific key
kubectl get secret doppler-env-secrets -n galaxy -o jsonpath='{.data.DOPPLER_SESSION_SECRET}' | base64 -d
```

## After Secret Changes

Always restart the deployment to load new secret values:

```bash
kubectl rollout restart deployment/<service> -n galaxy
kubectl rollout status deployment/<service> -n galaxy
```
