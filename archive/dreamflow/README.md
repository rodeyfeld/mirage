# dreamflow (archived 2026-10-10)

Airflow imagery pipeline, superseded by noctis (Prefect). Removed from the galaxy cluster;
these manifests are kept for reference only and are not applied by any pipeline.

- Backups on the galaxy server, in `/root/archive/`:
  - `dreamflow-db-20261010.dump`: `pg_dump -Fc` of the `dreamflow` database in atlas, which had no tables.
  - `dreamflow-k8s-20261010.yaml`: the live objects as removed, including secrets.
- Secrets: still in cuneiform at `galaxy-kv/prod/dreamflow`; policy in `dreamflow-policy.hcl`.
- Source: the `dreamflow` repo (archived on GitHub).
