Kubernetes files for pinwheel labs

kubectl create secret generic augur-env-secrets \
  --from-literal=AUGUR_SECRET_KEY=$AUGUR_SECRET_KEY \
  --from-literal=AUGUR_ALLOWED_HOSTS=$AUGUR_ALLOWED_HOSTS \
  --from-literal=AUGUR_DB_USER=$AUGUR_DB_USER \
  --from-literal=AUGUR_DB_PASSWORD=$AUGUR_DB_PASSWORD \
  --namespace=galaxy \
  --dry-run=apply -o yaml | kubectl apply -f -


