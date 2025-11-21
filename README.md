# Mirage

Kubernetes deployment manifests for the Galaxy cluster.

## Services

- **Luna** - SvelteKit frontend (https://luna.pinwheel.fan)
- **Augur** - Django REST API (https://augur.pinwheel.fan)
- **Atlas** - PostgreSQL 17 + PostGIS database
- **Doppler** - Go photoblog (https://pinwheel.fan)
- **Dreamflow** - Apache Airflow for data pipelines
- **Garage** - S3-compatible object storage

## Deployment

### 1. Create Namespace

```bash
kubectl apply -f namespace.yml
```

### 2. Create Secrets

See the `constellation` repository for secret creation commands.

### 3. Apply Volumes

```bash
kubectl apply -f volumes/atlas.yml
kubectl apply -f volumes/garage.yml
```

### 4. Deploy Services

```bash
# Database first
kubectl apply -f deployments/atlas.yml
kubectl apply -f services/atlas.yml

# API service
kubectl apply -f deployments/augur.yml
kubectl apply -f services/augur.yml

# Run database migrations
kubectl apply -f jobs/augur-db-migrate.yml
kubectl wait --for=condition=complete job/augur-db-migrate -n galaxy --timeout=5m
kubectl delete job/augur-db-migrate -n galaxy

# Frontend
kubectl apply -f deployments/luna.yml
kubectl apply -f services/luna.yml

# Other services
kubectl apply -f deployments/doppler.yml
kubectl apply -f services/doppler.yml
kubectl apply -f deployments/dreamflow.yml
kubectl apply -f services/dreamflow.yml
kubectl apply -f deployments/garage.yml
kubectl apply -f services/garage.yml
```

### 5. Configure Ingress

```bash
kubectl apply -f ingress.yml
```

## Updating Services

### Update Docker Image

```bash
# Build and push new image locally
cd ~/universe/luna
docker build --target prod -t edrodefeld/luna .
docker push edrodefeld/luna:latest

# Deploy on Hetzner
kubectl rollout restart deployment/luna -n galaxy
kubectl rollout status deployment/luna -n galaxy
```

### Update Configuration

```bash
# Edit deployment YAML locally
vim deployments/augur.yml

# Commit and push
git add deployments/augur.yml
git commit -m "Update Augur config"
git push

# Apply on Hetzner
cd ~/mirage
git pull
kubectl apply -f deployments/augur.yml
```

### Update Secrets

```bash
# Patch a secret value
kubectl patch secret augur-env-secrets -n galaxy \
  --type='json' \
  -p='[{"op": "replace", "path": "/data/AUGUR_DEBUG", "value": "'$(echo -n "False" | base64)'"}]'

# Restart to pick up changes
kubectl rollout restart deployment/augur -n galaxy
```

### Re-run Migrations

```bash
kubectl apply -f jobs/augur-db-migrate.yml
kubectl wait --for=condition=complete job/augur-db-migrate -n galaxy --timeout=5m
kubectl logs job/augur-db-migrate -n galaxy
kubectl delete job/augur-db-migrate -n galaxy
```

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -n galaxy
kubectl describe pod <pod-name> -n galaxy
kubectl logs <pod-name> -n galaxy --tail=100
```

### Check Service Connectivity

```bash
# Test from one pod to another
kubectl exec -n galaxy deployment/luna -- wget -O- http://augur-service:8000/api/providers/

# Check service endpoints
kubectl get svc -n galaxy
kubectl get endpoints -n galaxy
```

### Check Ingress

```bash
kubectl get ingress -n galaxy
kubectl describe ingress galaxy-ingress -n galaxy
```

### Force Pod Restart

```bash
kubectl delete pod -l name=augur -n galaxy
kubectl rollout status deployment/augur -n galaxy
```

## Security

- **External traffic**: HTTPS via Traefik + Let's Encrypt
- **Internal traffic**: HTTP within cluster (encrypted by network overlay)
- **Secrets**: Stored in Kubernetes secrets, referenced by deployments
- **CORS**: Augur only accepts requests from luna.pinwheel.fan
- **ALLOWED_HOSTS**: Augur validates Host headers for both external and internal requests

## Architecture

```
Internet → Traefik (HTTPS) → Services
                              ├─ Luna (SvelteKit)
                              ├─ Augur (Django API)
                              ├─ Dreamflow (Airflow)
                              └─ Garage (S3)

Internal:
Luna → Augur (HTTP) → Atlas (PostgreSQL)
Augur → Dreamflow (HTTP)
Doppler → Dreamflow (HTTP)
```
