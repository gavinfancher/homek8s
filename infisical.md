## secrets from infisical into the cluster

app secrets live in infisical cloud, not in git. the infisical secrets operator copies them into normal
k8s Secrets, and pods read those with `secretKeyRef` / `envFrom` like any other Secret. when a value
changes in infisical, the operator updates the Secret and restarts the pods that use it. no commit needed.

### how it fits together

```
infisical cloud (us, app.infisical.com)
  project k8s-test-7-nrf ─ env prod ─ folder /hello ─ GREETING
     │
     │  operator logs in as machine identity homek8s-operator (universal auth, viewer on the project)
     │  using secret infisical-machine-identity, and polls every resyncInterval (60s)
     ▼
InfisicalSecret nginxtest/hello-secrets     (in git: apps/hello/k8s/infisical-secret.yaml, no values)
     │  creates + updates
     ▼
Secret nginxtest/hello-secrets              (made by the operator, never by hand or git)
     │  secretKeyRef
     ▼
Deployment hello ── env GREETING ── nginx template ── shown on https://hello.k8s.ad.gavinf.com
     ▲
     └─ annotation secrets.infisical.com/auto-reload: "true" -> operator rolls the pods when the Secret changes
```

- **why infisical and not sealed secrets:** values are edited in a ui, not re-sealed and committed, and
  the same store can feed local dev and github actions later.
- **why cloud and not self-hosted:** self-hosting infisical on this cluster would make the cluster's
  secrets depend on an app running inside the cluster, which breaks a rebuild from scratch.
- **why universal auth and not kubernetes auth:** kubernetes auth needs infisical cloud to call this
  cluster's api server, which isn't reachable from the internet. universal auth only needs outbound https.
- **the one secret not in infisical:** `infisical-machine-identity` (the operator's own login). it's made
  by hand, same as `cloudflare-api-token`. if the cluster is rebuilt, recreate it (step 3 below).

### files

| file | what |
|---|---|
| `infra/infisical/helmchart.yaml` | installs the operator (chart `secrets-operator` 0.11.11) through k3s's helm controller into `infisical-operator-system` |
| `apps/hello/k8s/infisical-secret.yaml` | `InfisicalSecret` that syncs `prod:/hello` into Secret `nginxtest/hello-secrets` |
| `apps/hello/k8s/hello.yaml` | Deployment has the `auto-reload` annotation and `GREETING` from `secretKeyRef` |
| `apps/hello/k8s/kustomization.yaml` | lists `infisical-secret.yaml` so argo deploys it |
| `apps/hello/site/default.conf.template` | `set $greeting "${GREETING}";`. the nginx image runs envsubst on `/etc/nginx/templates/*.template` at startup |
| `apps/hello/site/index.html` | prints it with ssi: `<!--# echo var="greeting" -->` |

### current status (2026-10-20)

| thing | state |
|---|---|
| infisical org / project | us region, project slug `k8s-test-7-nrf`, project id `e72d83bd-1dce-466d-bf16-620efbb79bf0` |
| environments | `dev`, `staging`, `prod`. the cluster only reads `prod` |
| folders in prod | `/hello` -> `GREETING` (test value, safe to show) |
| machine identity | `homek8s-operator`, universal auth, org role no access/member, **viewer on the whole project** |
| operator | helmchart 0.11.11, deployment `infisical-secre-controller-manager` 1/1 running |
| bootstrap secret | `infisical-operator-system/infisical-machine-identity` with keys `clientId`, `clientSecret`. made by hand, not in git |
| InfisicalSecrets | `nginxtest/hello-secrets`. `LoadedInfisicalToken`, `ReadyToSyncSecrets`, `AutoRedeployReady` all True, synced 1 secret |
| hello app | argo synced + healthy, 3 pods, `GREETING` in env and on the page |
| tested end to end | edit in infisical -> Secret updated -> pods rolled -> new value on the page, about 60s, no commit |

### how it was set up (only needed again on a fresh cluster or new infisical account)

1. **infisical project** (ui): project, then in **Production** a folder per app (`hello`) with its keys inside.
2. **machine identity** (ui): org settings -> access control -> identities -> create `homek8s-operator`,
   universal auth, create a client secret (shown once, keep it in the password manager). then in the
   project -> access control -> machine identities -> add it as **viewer**.
3. **bootstrap secret**: the human runs this, so the client secret never goes through an agent or
   shell history:
   ```sh
   read "CID?Client ID: "; read -s "CSEC?Client secret: "; echo
   kubectl -n infisical-operator-system create secret generic infisical-machine-identity \
     --from-literal=clientId="$CID" --from-literal=clientSecret="$CSEC"
   unset CID CSEC
   ```
   key names must be exactly `clientId` and `clientSecret`. check with `describe secret` (sizes about
   36 and 64 bytes, never 0).
4. **operator**: `kubectl apply -f infra/infisical/helmchart.yaml` (infra/ isn't managed by argo).
5. **apps**: commit the `InfisicalSecret` + Deployment changes and let argo sync.

### adding secrets to another project

an agent can do the repo side. the infisical ui side and anything touching credentials is the human's.

**what the agent needs from the human first:**
- the app name and its **namespace** (Secrets only work inside their own namespace, so the
  InfisicalSecret, the Secret it makes, and the pods all have to share one)
- confirmation that the folder exists in infisical **Production** (e.g. `/blog`) with the keys in it, and
  the list of **key names** (not values) the app needs as env vars
- whether the app needs secrets shared with another app (then use a shared folder like `/shared` and
  one InfisicalSecret per namespace pointing at it)
- whether the app needs its own machine identity. not needed now (one user, one identity), see security below

**what the agent then does (repo only):**
1. add `apps/<app>/k8s/infisical-secret.yaml`. copy hello's and change `metadata.name`,
   `metadata.namespace`, `secretsPath`, and the `managedKubeSecretReferences` name + namespace.
   leave `hostAPI`, `projectSlug`, `envSlug`, `credentialsRef` as they are.
2. add it to `apps/<app>/k8s/kustomization.yaml` `resources`.
3. in the Deployment: add `secrets.infisical.com/auto-reload: "true"` under `metadata.annotations`, and
   wire the keys in with `env[].valueFrom.secretKeyRef` (or `envFrom.secretRef` for the whole folder).
4. validate: `kubectl kustomize apps/<app>/k8s` and
   `kubectl apply --dry-run=server -f apps/<app>/k8s/infisical-secret.yaml`.
5. hand over to the human to commit and push. argo needs an `infra/argocd/apps/<app>.yaml`
   Application if the app is new (copy `hello.yaml`).

**safe rollout order:** if the pods reference a Secret that doesn't exist yet, new pods sit in
`CreateContainerConfigError` (old ones keep running). so either have the human
`kubectl apply -f apps/<app>/k8s/infisical-secret.yaml` first and confirm it synced, or make sure the
folder and keys exist in infisical before pushing.

**don't:**
- put secret values in git, in chat, or in commands an agent runs
- create the target Secret by hand. the operator owns it (`creationPolicy: Owner`)
- point one InfisicalSecret at a different namespace than its own. ownership can't cross namespaces,
  so cleanup breaks
- run `kubectl apply` / `delete` against the cluster without asking. hand the human the command
  instead. read-only `get`/`describe`/`logs` are fine

### checking / monitoring

```sh
# did it log in and sync? Type is the LAST line of each condition, so use -B, not -A
kubectl -n <ns> describe infisicalsecret <name> | grep -B4 'Type:.*secrets.infisical'

# what's in the Secret (key names + sizes only)
kubectl -n <ns> describe secret <name>

# watch a change roll through
kubectl -n <ns> get pods -l app=<app> -w
kubectl -n infisical-operator-system logs deploy/infisical-secre-controller-manager -f

# force a sync now instead of waiting up to 60s
kubectl -n infisical-operator-system rollout restart deploy
```

`AutoRedeployReady` says "found 0 deployments" until the condition flips, so the message goes stale.
the real proof is the operator's `secrets.infisical.com/managed-secret.<name>` annotation on the
Deployment, and pods restarting after a change.

### troubleshooting

| symptom | cause |
|---|---|
| `LoadedInfisicalToken` False / 401 | bad or rotated client id/secret. recreate `infisical-machine-identity` |
| 403 | identity isn't a member of the project (needs viewer) |
| 404 `Folder with path '/x' in environment 'prod' was not found` | folder missing, made in the wrong env (we hit this: it was in dev), or env slug isn't `prod` |
| pods `CreateContainerConfigError` | the Secret or key doesn't exist yet. check the InfisicalSecret status |
| value changed in infisical, pods didn't restart | Deployment missing the `auto-reload` annotation, or wait out `resyncInterval` |

### security notes

- one machine identity reads the **whole** project. anyone who can create an InfisicalSecret in any
  namespace can pull any folder. fine with one user on a home cluster. if that changes, make one identity
  per app, limit its role to that app's folder, and give it its own credentials secret.
- `GREETING` is shown on a web page only because it's a test value. never render real secrets.
- k3s stores Secrets in the datastore unencrypted unless `secrets-encryption` is turned on.
- the operator chart is pinned. bump `version` in `infra/infisical/helmchart.yaml` on purpose, and check
  the CRD fields with `kubectl explain infisicalsecret.spec` after upgrading (the operator also has a
  newer split api, InfisicalConnection / InfisicalAuth / InfisicalStaticSecret, which we don't use).
