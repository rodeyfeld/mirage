# Mirage

All the k8s manifests for the galaxy cluster running on Hetzner.

## Deploying everything

1. Make the namespace:

   ```bash
   kubectl apply -f namespace.yml
   ```

2. Create secrets (check the constellation repo for commands)

3. Set up storage:

   ```bash
   kubectl apply -f volumes/atlas.yml
   kubectl apply -f volumes/garage.yml
   ```

4. Deploy stuff in order:

   ```bash
   # Database first
   kubectl apply -f deployments/atlas.yml
   kubectl apply -f services/atlas.yml

   # API layer
   kubectl apply -f deployments/augur.yml
   kubectl apply -f services/augur.yml

   # Run migrations
   kubectl apply -f jobs/augur-db-migrate.yml
   kubectl wait --for=condition=complete job/augur-db-migrate -n galaxy --timeout=5m
   kubectl delete job/augur-db-migrate -n galaxy

   # Frontend
   kubectl apply -f deployments/luna.yml
   kubectl apply -f services/luna.yml

   # Everything else
   kubectl apply -f deployments/doppler.yml
   kubectl apply -f services/doppler.yml
   kubectl apply -f deployments/dreamflow.yml
   kubectl apply -f services/dreamflow.yml
   kubectl apply -f deployments/garage.yml
   kubectl apply -f services/garage.yml
   ```

5. Set up ingress:
   ```bash
   kubectl apply -f ingress.yml
   ```

## Updating a service

```bash
# Build locally
cd ~/universe/luna
docker build --target prod -t edrodefeld/luna .
docker push edrodefeld/luna:latest

# Deploy
kubectl rollout restart deployment/luna -n galaxy
kubectl rollout status deployment/luna -n galaxy
```
