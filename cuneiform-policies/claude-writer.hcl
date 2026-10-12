# Claude's Bao token (made by claude-token.sh). Write-only: it can set a value
# in any app's path (patch-key.sh) but never read one back. Not named
# *-policy.hcl, so sync.sh leaves it alone; claude-token.sh writes it.
path "galaxy-kv/data/prod/*" {
  capabilities = ["create", "update", "patch"]
}

# The app paths that exist (names only, no values).
path "galaxy-kv/metadata/prod/*" {
  capabilities = ["list"]
}
