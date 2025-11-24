#!/bin/bash
# Apply Cuneiform policies for Universe services
# Usage: ./apply-policies.sh [root-token]
# If token not provided, will prompt for it (avoids shell history)

set -e

# Get token from argument or prompt
if [ -n "$1" ]; then
  TOKEN=$1
elif [ -n "$BAO_TOKEN" ]; then
  TOKEN=$BAO_TOKEN
else
  read -s -p "Enter OpenBao Root Token: " TOKEN
  echo ""
fi

if [ -z "$TOKEN" ]; then
  echo "Error: No token provided"
  exit 1
fi

POD=$(kubectl get pod -n galaxy -l name=cuneiform -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POD" ]; then
  echo "Error: Could not find cuneiform pod in galaxy namespace"
  exit 1
fi

echo "Applying policies to Cuneiform pod: $POD"
echo ""

# Pre-flight checks
echo "Running pre-flight checks..."
kubectl exec -n galaxy $POD -- sh -c "
export BAO_ADDR=http://127.0.0.1:8200
export BAO_TOKEN=$TOKEN

# Check if sealed
if bao status | grep -q 'Sealed.*true'; then
  echo 'Error: OpenBao is sealed. Unseal it first.'
  exit 1
fi

# Check/enable Kubernetes auth
if ! bao auth list | grep -q 'kubernetes/'; then
  echo 'Enabling Kubernetes auth method...'
  bao auth enable kubernetes
fi

# Check/enable KV engine
if ! bao secrets list | grep -q 'galaxy-kv/'; then
  echo 'Error: galaxy-kv secrets engine not found'
  exit 1
fi

echo 'Pre-flight checks passed ✓'
"

echo ""
echo "Configuring Kubernetes auth method..."
kubectl exec -n galaxy $POD -- sh -c "
export BAO_ADDR=http://127.0.0.1:8200
export BAO_TOKEN=$TOKEN

# Configure Kubernetes auth
bao write auth/kubernetes/config \
  token_reviewer_jwt=\"\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)\" \
  kubernetes_host=\"https://kubernetes.default.svc:443\" \
  kubernetes_ca_cert=\"\$(cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt)\" \
  disable_iss_validation=true
"

echo ""
echo "Creating policies..."

# Apply each policy
for policy in atlas augur doppler dreamflow ouroboros garage; do
  echo "Creating policy: ${policy}-policy"
  kubectl exec -n galaxy $POD -- sh -c "
    export BAO_ADDR=http://127.0.0.1:8200
    export BAO_TOKEN=$TOKEN
    bao policy write ${policy}-policy - <<'EOF'
$(cat ${policy}-policy.hcl)
EOF
  "
done

echo ""
echo "Creating Kubernetes auth roles..."

# Create roles that bind policies to service accounts
kubectl exec -n galaxy $POD -- sh -c "
export BAO_ADDR=http://127.0.0.1:8200
export BAO_TOKEN=$TOKEN

# Atlas role - bound to atlas ServiceAccount
bao write auth/kubernetes/role/atlas \
  bound_service_account_names=atlas \
  bound_service_account_namespaces=galaxy \
  policies=atlas-policy \
  ttl=24h

# Augur role - bound to augur ServiceAccount
bao write auth/kubernetes/role/augur \
  bound_service_account_names=augur \
  bound_service_account_namespaces=galaxy \
  policies=augur-policy \
  ttl=24h

# Doppler role - bound to doppler ServiceAccount
bao write auth/kubernetes/role/doppler \
  bound_service_account_names=doppler \
  bound_service_account_namespaces=galaxy \
  policies=doppler-policy \
  ttl=24h

# Dreamflow role - bound to dreamflow ServiceAccount (webserver, worker, scheduler)
bao write auth/kubernetes/role/dreamflow \
  bound_service_account_names=dreamflow \
  bound_service_account_namespaces=galaxy \
  policies=dreamflow-policy \
  ttl=24h

# Ouroboros role - bound to ouroboros ServiceAccount
bao write auth/kubernetes/role/ouroboros \
  bound_service_account_names=ouroboros \
  bound_service_account_namespaces=galaxy \
  policies=ouroboros-policy \
  ttl=24h

# Garage role - bound to garage ServiceAccount
bao write auth/kubernetes/role/garage \
  bound_service_account_names=garage \
  bound_service_account_namespaces=galaxy \
  policies=garage-policy \
  ttl=24h
"

echo ""
echo "✅ All policies and roles created successfully!"
echo ""
echo "Summary:"
echo "  - Kubernetes auth: configured"
echo "  - Policies created: 6 (atlas, augur, doppler, dreamflow, ouroboros, garage)"
echo "  - Roles created: 6 (bound to ServiceAccounts)"
echo ""
echo "Next step: Update deployments to use the new ServiceAccounts"

