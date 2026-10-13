# The lab

The owner's experiments at `https://<project>.lab.pinwheel.fan`: repos in the forge's
`lab` org, workloads in the `lab` namespace on galaxy, looked after by the **lab
mycologist**: mycelia's spore with profile `"lab"`, service account `lab-mycologist`
(`apps/spores/lab-mycologist.yml`), guide `mycelia/spore/lab.md`, command `lab`.

Above it is the **owner's own mycologist**, the highest level (today's mycologist). It
owns the base sites, schematics and the rest, and can read and steer the lab mycologist,
which can't read or steer it. The owner can always reach it at
mycelia.pinwheel.fan/mycologist.

What keeps the lab in the lab (enforced, not just written down):

| Where | How |
|-------|-----|
| k8s | the lab mycologist is `edit` in `lab` only; `lab` is pod-security `restricted`, with a quota and a NetworkPolicy (no atlas, no galaxy services) |
| mirage | it can push only `apps/lab-*/**` (branch protection); `ci/lab-guard.sh` fails the pipeline, before anything is synced or applied, if a lab app has an object outside `lab` or a secret outside its own |
| forge | it's admin of the `lab` org only; `rodeyfeld/*` aren't its |
| Woodpecker | its own user's token, not the owner's admin one |
| Hetzner | its own `lab` project, not galaxy's |
| databases | `lab-postgres` in the namespace; atlas isn't reachable from the lab |
| secrets | cuneiform `galaxy-kv/prod/mycelia`: `lab_mycologist_git_token`, `lab_mycologist_woodpecker_token`, `lab_hcloud_token` |

**Not fenced yet: CI.** See "Before step 10" below.

## Setting it up (once, in order)

**The owner** (things only a person can do):

1. *(done 2026-10-13, mirage d46a05f)* On ouroboros, close open registration:
   `WOODPECKER_OPEN: "false"` (`apps/ouroboros/configmap.yml`). Existing users keep
   working; new ones are added by an admin (step 4).
2. *(done 2026-10-13)* In the Hetzner console: a project `lab`, and a read/write API token for it. (Delete and
   rebuild protection on `pinwheel` and `schematics` were already on, checked 2026-10-13.)
3. On schematics, as an admin:
   - *(done 2026-10-13)* the user `lab-mycologist` (id 5);
   - *(done 2026-10-13 by the owner's mycologist)* the org `lab`, with `lab-mycologist` and `rodeyfeld` as owners;
   - **held back** (see "Before step 10"): `lab-mycologist` as a writer on `rodeyfeld/mirage`;
   - *(done 2026-10-13)* a token for `lab-mycologist` with write:repository, write:organization and
     write:package;
   - *(done 2026-10-13 by the owner's mycologist)* on `rodeyfeld/mirage`'s `main`, branch protection: push only for the whitelisted
     users (rodeyfeld), **unprotected file patterns** `apps/lab-*/**`, so that
     lab-mycologist's write access reaches only those files.
4. *(done 2026-10-13; lab-mycologist is Woodpecker user 3)* In ouroboros' admin settings, add the user `lab-mycologist` (registration is closed),
   then sign in once as it and make its personal token.
   - **Gotcha:** a user added in the admin UI gets `forge_id=0, forge_remote_id=0`, and its
     first Forgejo sign-in fails with "cannot register <login>. registration closed" (in
     the ouroboros-server logs). Fix: back up `woodpecker-forgejo.sqlite`, then set
     `forge_id=1, forge_remote_id=<Forgejo user id>` in its `users` row; no restart needed.
     (Done for lab-mycologist; backup `wp-bak-1013.sqlite` in the ouroboros PVC.)
   - Woodpecker keeps **one token per user**: resetting lab-mycologist's token breaks the
     copy in cuneiform.
5. *(done 2026-10-13)* Put the three tokens in cuneiform with `cuneiform-policies/patch-key.sh mycelia ...`:
   `lab_mycologist_git_token`, `lab_mycologist_woodpecker_token`, `lab_hcloud_token`.
   Do this **before** step 8; `apps/mycelia/secrets.yml` needs them.

**The owner's mycologist** (it can do these today, with the owner's yes):

6. *(done 2026-10-13)* DNS: a new A record `*.lab.pinwheel.fan` → 5.161.236.179,
   TTL 86400. The org `lab` also exists (done 2026-10-13, private, rodeyfeld its owner): step 3
   only adds `lab-mycologist` to it.
7. *(done 2026-10-13)* `kubectl apply -f apps/lab/namespace.yml -f apps/lab/to-lab.yml -f apps/spores/lab-mycologist.yml`.
8. Merge mirage's `lab` branch. Its pipeline runs `lab-guard`, syncs `lab-postgres`'s and
   `lab-pothos`'s secrets into `lab`, and applies `lab-postgres` (the lab-perigee and
   lab-pothos deployments wait for their images, from the moves below).
9. *(done 2026-10-13: mycelia main 7b4ba7e)* Merge mycelia's `mycelium` branch: mycologists by rank, `/owner's mycologist`, the `lab`
   command and templates, `spore/lab.md`. Once the new spore image is built, delete the
   owner's mycologist's pod, so it comes back on the new image.
10. Set `MYCELIA_LAB_MYCOLOGIST: "on"` (`apps/mycelia/configmap.yml`). mycelia makes the
    lab mycologist, and it gets its bearings.

**Before step 10: fence CI** (found 2026-10-13, the owner's call)

Every Woodpecker pipeline, whoever triggers it, runs its step pods in `galaxy` as
`ouroboros-deployer` (`WOODPECKER_BACKEND_K8S_SERVICE_ACCOUNT`), which the
ClusterRoleBinding `ouroboros-deployer-binding` gives full secrets/pods/deployments
rights in **every** namespace. A pipeline's steps come from its own `.woodpecker.yml`,
so once lab-mycologist can trigger one (any repo in `lab`, or any branch it pushes to
mirage; the branch protection covers `main` only), it can read every secret in the
cluster. On mirage it would also get the org secret `cuneiform_token`, which reaches
push events on any branch, and mirage needs approval only for forks. To decide:

- Lab pipelines on their own agent: an org agent for `lab`, with
  `WOODPECKER_BACKEND_K8S_NAMESPACE=lab` and a service account limited to `lab`, and
  galaxy's agent kept from taking lab pipelines (check how v3.13 routes org agents).
- `ouroboros-deployer-binding` as a RoleBinding in `galaxy` only, not cluster-wide.
- Either no mirage Write for lab-mycologist (the lab agent applies `apps/lab-*` itself),
  or mirage's `require_approval` set to all events with `approval_allowed_users`
  [rodeyfeld], so a lab-mycologist push waits for the owner.

Until then, keep `MYCELIA_LAB_MYCOLOGIST` off and lab-mycologist off mirage.

**The lab mycologist** (its first jobs):

11. In Woodpecker, the `lab` org's secrets `docker_username` (`lab-mycologist`) and
    `docker_password` (its forge token), so lab pipelines can push images.
12. Check the branch protection: a push to mirage touching anything outside `apps/lab-*/`
    must be rejected.
13. `lab drill`. It should report under 5 minutes.

## Moving perigee and pothos (the owner's mycologist)

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

**reverie** (mirage 4e4afb1) already answers at `reverie.lab.pinwheel.fan`, but from the
`galaxy` namespace, outside the lab's quota and policies. Move it the same way as perigee
once the lab is up: repo to `lab/`, manifests to `apps/lab-reverie/` in `lab`.

## Good to know

- Spore pods outlive deploys: after an env or secret change, delete the pod to pick it
  up. Its PVC stays.

## Later

- kami shows `lab`'s rollouts (today it watches galaxy's), so stuck lab rollouts are
  summoned too.
- Secrets by reference in spore pods, so no pod spec carries a token inline.
