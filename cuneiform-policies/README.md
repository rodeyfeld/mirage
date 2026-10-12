# Cuneiform (OpenBao) policies and app secrets

The mirage pipeline's `sync-secrets` step runs `sync.sh apply` on every push to
`main`. Nothing here is run by hand.

## What it does

1. **Policies.** Every `<app>-policy.hcl` here is written to cuneiform as
   `<app>-policy`, with a Kubernetes auth role `<app>` that binds it to the
   `<app>` ServiceAccount in `galaxy`. Unchanged ones are skipped.
2. **Secrets.** Every `apps/<app>/secrets.yml` names a cuneiform path and the
   k8s Secret to build from it:

   ```yaml
   path: galaxy-kv/prod/mycelia      # KV v2 path in cuneiform
   secret: mycelia-env-secrets       # k8s Secret in galaxy
   generate:                         # created once if missing; never overwritten
     postgres_password: alnum-32     # alnum-N | base64-N | hex-N
   env:                              # Secret key -> template
     POSTGRES_PASSWORD: "{postgres_password}"
     DATABASE_URL: "ecto://mycelia:{postgres_password}@mycelia-postgres:5432/mycelia_prod"
     ATLAS_DB_PASSWORD: "{atlas.postgres_password}"   # another app's path
     WOODPECKER_HOST: "https://ouroboros.pinwheel.fan" # plain literal
   ```

   A template referencing a key that cuneiform doesn't have fails that app
   (its Secret is left as it was) instead of writing an empty or `null` value.

## Common tasks

- **New app:** add `apps/<app>/secrets.yml` (and `<app>-policy.hcl` here),
  push. Generated values appear in cuneiform and the Secret on that run.
- **New generated key:** add it under `generate:` and `env:`, push.
- **Rotate a generated value:** delete the key in cuneiform
  (`bao kv patch -remove-data=<key> galaxy-kv/prod/<app>`), push.
- **A value you choose** (third-party API key, a password you pick): it has to
  be written once, by someone holding a Bao token:
  `./patch-key.sh <app> <key> [ENV_VAR]` (prompts for the token and the value,
  or takes the value from `$ENV_VAR`, and sends both over ssh on stdin).
  Then reference it in `env:` and push.
- **Claude's token:** `./claude-token.sh` (run once, with an admin token) writes
  the `claude-writer` policy (`claude-writer.hcl`: create/update/patch under
  `galaxy-kv/data/prod/*`, no read) and saves a periodic 30-day token to
  `~/.config/cuneiform/env`. Claude runs `patch-key.sh` with it, which renews it
  on each use. Revoke it with `bao token revoke -accessor <accessor>` (find it
  with `bao list auth/token/accessors`).
- **Read a value** (e.g. mycelia's basic-auth password):
  `bao kv get -field=basic_auth_password galaxy-kv/prod/mycelia`, or from the
  live Secret: `k3s kubectl -n galaxy get secret mycelia-env-secrets -o jsonpath='{.data.MYCELIA_BASIC_AUTH_PASSWORD}' | base64 -d`.

## Dry run

`sync.sh check` changes nothing and reports drift by key name only (never
values). It needs `BAO_ADDR`/`BAO_TOKEN`, `curl`, `jq`, `yq` v4 and `kubectl`.
If the vault is sealed the run stops with the unseal hint.
