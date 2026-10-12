# The owner's everyday login (userpass `rodeyfeld`, made by operator-setup.sh),
# so the root token can stay put away. Covers what running galaxy needs: every
# KV path, policies, k8s auth roles, userpass users, minting and revoking
# tokens. Not seal/unseal, rekey, generate-root or enabling auth methods.
# Not named *-policy.hcl, so sync.sh leaves it alone.

path "galaxy-kv/*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list"]
}

path "sys/policies/acl" {
  capabilities = ["list"]
}

path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "auth/kubernetes/role/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "auth/userpass/users/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# sudo: a child token may carry policies this one doesn't have (e.g.
# claude-writer). Root policy still needs a root parent.
path "auth/token/create" {
  capabilities = ["create", "update", "sudo"]
}

path "auth/token/create-orphan" {
  capabilities = ["create", "update", "sudo"]
}

path "auth/token/accessors" {
  capabilities = ["list", "sudo"]
}

path "auth/token/lookup-accessor" {
  capabilities = ["update"]
}

path "auth/token/revoke-accessor" {
  capabilities = ["update"]
}

# What sync.sh probes.
path "sys/capabilities-self" {
  capabilities = ["update"]
}

path "sys/auth" {
  capabilities = ["read"]
}

path "sys/mounts" {
  capabilities = ["read"]
}
