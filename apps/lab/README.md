# The lab

The owner's experiments at `https://<project>.lab.pinwheel.fan`: repos in the forge's
`lab` org, workloads in the `lab` namespace on galaxy, looked after by the **ovate**, the
lab's mycologist. Mycologists are ranked like a druid order: archdruid, ovate, bard. The
ovate is mycelia's spore with rank `"ovate"`: its service account is `lab-mycologist`
(`apps/spores/lab-mycologist.yml`), its guide `mycelia/spore/lab.md`, its command `lab`.
The **archdruid** (today's mycologist, the highest rank) is above it: it owns the base
sites, schematics and the rest, and can read and steer the ovate, which can't read or
steer it. The owner can always reach the archdruid at mycelia.pinwheel.fan/archdruid.

What keeps the lab in the lab (enforced, not just written down):

| Where | How |
|-------|-----|
| k8s | the ovate is `edit` in `lab` only; `lab` is pod-security `restricted`, with a quota and a NetworkPolicy (no atlas, no galaxy services) |
| mirage | it can push only `apps/lab-*/**` (branch protection); `ci/lab-guard.sh` fails the pipeline, before anything is synced or applied, if a lab app has an object outside `lab` or a secret outside its own |
| forge | it's admin of the `lab` org only; `rodeyfeld/*` aren't its |
| Woodpecker | its own user's token, not the owner's admin one |
| Hetzner | its own `lab` project, not galaxy's |
| databases | `lab-postgres` in the namespace; atlas isn't reachable from the lab |

## Setting it up (once, in order)

**The owner** (things only a person can do):

1. On ouroboros, close open registration: `WOODPECKER_OPEN: "false"` and
   `WOODPECKER_ORGS: "rodeyfeld,lab"` (`apps/ouroboros/configmap.yml`), so only members of
   those two orgs can sign in.
2. In the Hetzner console: a project `lab`, and a read/write API token for it. Also turn on
   delete and rebuild protection for `pinwheel` (galaxy) and `schematics` in theirs.
3. On schematics, as an admin:
   - the user `lab-mycologist`;
   - the org `lab`, with `lab-mycologist` and `rodeyfeld` as owners;
   - `lab-mycologist` as a writer on `rodeyfeld/mirage`;
   - a token for `lab-mycologist` with write:repository, write:organization and
     write:package;
   - on `rodeyfeld/mirage`'s `main`, branch protection: push only for the whitelisted
     users (rodeyfeld), **unprotected file patterns** `apps/lab-*/**`, so that
     lab-mycologist's write access reaches only those files.
4. Sign in to ouroboros once as `lab-mycologist` and make its personal token.
5. Put the three tokens in cuneiform with `cuneiform-policies/patch-key.sh mycelia ...`:
   `lab_mycologist_git_token`, `lab_mycologist_woodpecker_token`, `lab_hcloud_token`.
   Do this **before** step 8; `apps/mycelia/secrets.yml` needs them.

**The archdruid** (it can do these today, with the owner's yes):

6. DNS: a new A record `*.lab.pinwheel.fan` → 5.161.236.179, TTL 86400.
7. `kubectl apply -f apps/lab/namespace.yml -f apps/lab/to-lab.yml -f apps/spores/lab-mycologist.yml`.
8. Merge mirage's `lab` branch. Its pipeline runs `lab-guard`, syncs `lab-postgres`'s and
   `lab-pothos`'s secrets into `lab`, and applies `lab-postgres` (the lab-perigee and
   lab-pothos deployments wait for their images, from the moves below).
9. Merge mycelia's `mycelium` branch: mycologists by rank, `/archdruid`, the `lab`
   command and templates, `spore/lab.md`. Once the new spore image is built, delete the
   archdruid's pod, so it comes back on the new image.
10. Set `MYCELIA_LAB_MYCOLOGIST: "on"` (`apps/mycelia/configmap.yml`). mycelia makes the
    ovate, and it gets its bearings.

**The ovate** (its first jobs):

11. In Woodpecker, the `lab` org's secrets `docker_username` (`lab-mycologist`) and
    `docker_password` (its forge token), so lab pipelines can push images.
12. Check the branch protection: a push to mirage touching anything outside `apps/lab-*/`
    must be rejected.
13. `lab drill`. It should report under 5 minutes.

## Moving perigee and pothos (the archdruid)

**perigee** has no data, so the move is a cutover:

1. Transfer `rodeyfeld/perigee` to `lab`; the forge redirects the old URL. Add `kami` as a
   reader. In its `.woodpecker.yml`, set `repo: schematics.pinwheel.fan/lab/perigee` and
   `-n lab`, then push. Turn it on in Woodpecker if the transfer turned it off.
2. When `https://perigee.lab.pinwheel.fan/readyz` answers (apply
   `apps/lab-perigee/ingress.yml`), take the old one down:
   `kubectl -n galaxy delete deploy/perigee svc/perigee-service ingress/perigee-ingress`,
   remove `apps/perigee/`, then `kubectl apply -f apps/lab/redirect-perigee.yml`.

**pothos** has a database on atlas, so its data comes over:

1. Transfer `rodeyfeld/pothos` to `lab`, as above. In its `.woodpecker.yml`, set
   `repo: schematics.pinwheel.fan/lab/pothos` and `-n lab`. Let the job
   `pothos-db-ensure` (in `lab`) make the role and database on lab-postgres.
2. `kubectl -n galaxy scale deploy/pothos --replicas=0`, then copy the data:
   `pg_dump -Fc` the `pothos` database from atlas, and `pg_restore --no-owner --role=pothos`
   it into lab-postgres. Both run from a throwaway pod in galaxy that can reach both
   (lab-postgres's service is in `lab`; the lab NetworkPolicy lets in only the lab and
   traefik, so give the pod `-n lab` and the atlas password as an env var, or run
   `pg_dump` in galaxy and `kubectl cp` the file across).
3. Push pothos (or rerun its pipeline). When `https://pothos.lab.pinwheel.fan/readyz`
   answers and a run plays, remove the old one: delete its galaxy deployment, service,
   ingress, configmap and job, remove `apps/pothos/`, then
   `kubectl apply -f apps/lab/redirect-pothos.yml`. Keep the `pothos` database on atlas
   for a week, then drop it and its role.

Players sign in again after the move (a new `secret_key_base`).

## Later

- kami shows `lab`'s rollouts (today it watches galaxy's), so stuck lab rollouts are
  summoned too.
- Secrets by reference in spore pods, so no pod spec carries a token inline.
