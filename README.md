Kubernetes files for pinwheel labs

## Setup Instructions

### 1. Configure Environment Variables

Copy the example environment file and fill in your values:

```bash
cp example.env .env
```

### 2. Create Kubernetes Secrets

Run these commands in order to set up all required secrets. Make sure your `.env` file is sourced first:

```bash
source .env
```

Then run the secret creation commands:

#### Augur (API Service)
```bash
kubectl create secret generic augur-env-secrets \
  --from-literal=AUGUR_SECRET_KEY=$AUGUR_SECRET_KEY \
  --from-literal=AUGUR_ALLOWED_HOSTS=$AUGUR_ALLOWED_HOSTS \
  --from-literal=AUGUR_DB_USER=$AUGUR_DB_USER \
  --from-literal=AUGUR_DB_PASSWORD=$AUGUR_DB_PASSWORD \
  --from-literal=AUGUR_CORS_ALLOWED_ORIGINS=$AUGUR_CORS_ALLOWED_ORIGINS \
  --from-literal=AUGUR_DREAMFLOW_USER=$AUGUR_DREAMFLOW_USER \
  --from-literal=AUGUR_DREAMFLOW_PASSWORD=$AUGUR_DREAMFLOW_PASSWORD \
  --namespace=galaxy
```

#### Atlas (PostgreSQL Database)
```bash
kubectl create secret generic atlas-env-secrets \
  --from-literal=POSTGRES_USER=$ATLAS_POSTGRES_USER \
  --from-literal=POSTGRES_PASSWORD=$ATLAS_POSTGRES_PASSWORD \
  --namespace=galaxy
```

#### Luna (Frontend)
```bash
kubectl create secret generic luna-env-secrets \
  --from-literal=LUNA_AUGUR_HOST=$LUNA_AUGUR_HOST \
  --namespace=galaxy
```

#### Dreamflow (Airflow)
```bash
kubectl create secret generic dreamflow-env-secrets \
  --from-literal=AIRFLOW_PROJ_DIR=$AIRFLOW_PROJ_DIR \
  --from-literal=AIRFLOW_HOME=$AIRFLOW_HOME \
  --from-literal=AIRFLOW_CONN_POSTGRES_DEFAULT=$AIRFLOW_CONN_POSTGRES_DEFAULT \
  --from-literal=AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=$AIRFLOW__DATABASE__SQL_ALCHEMY_CONN \
  --from-literal=AIRFLOW__CORE__SQL_ALCHEMY_CONN=$AIRFLOW__CORE__SQL_ALCHEMY_CONN \
  --namespace=galaxy
```

#### Oracle (Database Population Job)
```bash
kubectl create secret generic oracle-env-secrets \
  --from-literal=POSTGRES_DB_URL=$POSTGRES_DB_URL \
  --namespace=galaxy
```

#### Garage (S3-Compatible Storage)
```bash
kubectl create secret generic garage-secrets \
  --from-literal=GARAGE_RPC_SECRET=$(openssl rand -hex 32) \
  --namespace=galaxy
```

### 3. Deploy to Kubernetes

Apply resources in this order:

1. **Volumes:** `kubectl apply -f volumes/`
2. **ConfigMaps:** `kubectl apply -f configmaps/`
3. **Services:** `kubectl apply -f services/`
4. **Deployments:** `kubectl apply -f deployments/`
5. **Jobs** (optional): `kubectl apply -f jobs/`

### 4. Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n galaxy

# Check all services
kubectl get svc -n galaxy

# Check persistent volumes
kubectl get pv
kubectl get pvc -n galaxy
```

