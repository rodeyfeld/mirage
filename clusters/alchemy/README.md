# alchemy

The cluster for what isn't tied to a colony's box: a single-node k3s on its own Hetzner CX33
in nbg1. Today it runs **schematics**, Forgejo (git + container registry) at
`schematics.pinwheel.fan`. Planned (diagrams/universe-plan.md in the workspace): the
Woodpecker server, cuneiform, garage as S3 for colonies, and the backups. Separate from
galaxy so a broken galaxy doesn't take the source and images with it.

- Web: https://schematics.pinwheel.fan
- Git over SSH: `git@schematics.pinwheel.fan:<owner>/<repo>.git` (port 22 is Forgejo)
- Registry: `docker login schematics.pinwheel.fan`, then push `schematics.pinwheel.fan/<owner>/<image>:<tag>`
- The box itself: `ssh schematics` (host sshd is on **2222**)

Nothing here is applied by CI. ouroboros only reaches galaxy.

## Setting it up from scratch

```bash
# on the box: move sshd to 2222 (/etc/systemd/system/ssh.socket.d/port.conf), then k3s
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=<version> sh -

# from mirage/
ssh schematics 'k3s kubectl apply -f -' < cluster/cert-manager/cert-manager.yml
ssh schematics 'k3s kubectl apply -f -' < cluster/security/issuer-prod.yml

cd clusters/alchemy
ssh schematics 'mkdir -p /data/schematics/forgejo/{data,config} /data/schematics/postgres && chown -R 1000:1000 /data/schematics/forgejo'
for f in namespace middleware-https traefik-config; do ssh schematics 'k3s kubectl apply -f -' < $f.yml; done
ssh schematics 'bash -s' < bootstrap-secrets.sh
for f in pv pvc configmap statefulset deployment service ingress; do
  ssh schematics 'k3s kubectl apply -f -' < apps/schematics/$f.yml
done
```

Apply files one at a time; `cat`-ing them together merges the YAML documents.

Admin user: `forgejo admin user create --admin --username <name> --email <email> --random-password`
via `k3s kubectl -n schematics exec deploy/schematics -- ...`.

## Secrets

`bootstrap-secrets.sh` generates `schematics-env-secrets` (Postgres password and Forgejo's
secret key/tokens) once and never overwrites it. These move to cuneiform once it lives here.

## Upgrading Forgejo

The image is pinned to the `15-rootless` LTS line. Bump the tag in `deployment.yml` and apply.
