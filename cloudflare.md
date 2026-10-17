## https for *.k8s.ad.gavinf.com with cloudflare + let's encrypt

every app under `*.k8s.ad.gavinf.com` gets a real, browser-trusted cert, and http redirects to https.
one wildcard cert covers everything, so new apps just need an ingress, no tls config.

### how it fits together

```
cert-manager ──(cloudflare api token)──> creates TXT _acme-challenge.k8s.ad.gavinf.com in cloudflare
     │                                                    │
     │                         let's encrypt checks it on public dns
     ▼                                                    │
secret wildcard-k8s-ad-gavinf-com-tls  <──── signed cert ─┘
     │
     ▼
traefik TLSStore "default" ──> served for every https request on :443
```

- **why dns-01 and not http-01:** the cluster is only on the lan/tailscale, so let's encrypt can't reach
  it over http. with dns-01 you prove ownership by publishing a TXT record, which works for private
  clusters, and wildcard certs *require* it anyway.
- **why this works with split dns:** `ad.gavinf.com` is served internally by dc01, but publicly it isn't
  delegated anywhere, so cloudflare (the public dns for `gavinf.com`) answers for it. that's where let's
  encrypt looks.
- **the split dns gotcha:** before telling let's encrypt "go check", cert-manager checks the TXT record
  itself. by default it asks the cluster's resolver -> dc01, which owns `ad.gavinf.com` and will never see
  the cloudflare record, so it waits forever. fixed with
  `--dns01-recursive-nameservers-only --dns01-recursive-nameservers=1.1.1.1:53,8.8.8.8:53`.

### files

| file | what |
|---|---|
| `infra/cert-manager/helmchart.yaml` | installs cert-manager v1.21.2 through k3s's helm controller, with the public resolver flags |
| `infra/cert-manager/clusterissuers.yaml` | `letsencrypt-staging` and `letsencrypt-prod`, both solving dns-01 via cloudflare |
| `infra/traefik/wildcard-cert.yaml` | the `*.k8s.ad.gavinf.com` Certificate + the default TLSStore pointing at it |
| `infra/traefik/helmchartconfig.yaml` | `ports.web.http.redirections` sends http -> https (301) |

### steps

1. install cert-manager and the issuers
```
kubectl apply -f infra/cert-manager/helmchart.yaml
kubectl -n cert-manager get deploy        # wait for 3x 1/1
kubectl apply -f infra/cert-manager/clusterissuers.yaml
```

2. cloudflare api token: my profile -> api tokens -> create token -> "edit zone DNS" template,
   zone resources = include / specific zone / `gavinf.com`. then store it (never commit it):
```
kubectl -n cert-manager create secret generic cloudflare-api-token --from-literal=api-token=<token>
kubectl get clusterissuer                 # both READY True
```
issuer READY only means the let's encrypt account registered. the token isn't used until a cert is requested.

3. request the cert against **staging** first (untrusted certs, loose rate limits, mistakes are free).
   set `issuerRef.name: letsencrypt-staging` in `wildcard-cert.yaml`, then:
```
kubectl apply -f infra/traefik/wildcard-cert.yaml
kubectl get certificate,certificaterequest,order,challenge -n kube-system
```
the chain cert-manager builds:
```
Certificate          "i want *.k8s.ad.gavinf.com in this secret"
 └ CertificateRequest  private key + CSR
    └ Order              asked let's encrypt for a cert
       └ Challenge         "prove you control k8s.ad.gavinf.com" -> TXT record via cloudflare
```
watch the TXT record appear publicly (its value matches the challenge's `Key`):
```
kubectl describe challenge -n kube-system
dig +short TXT _acme-challenge.k8s.ad.gavinf.com @1.1.1.1
```
took ~80s to go READY. cert-manager deletes the TXT record afterwards.

4. switch `issuerRef.name` to `letsencrypt-prod` and apply again. changing the issuer triggers a
   reissue into the same secret, so traefik picks it up without a restart.
```
kubectl apply -f infra/traefik/wildcard-cert.yaml
kubectl -n kube-system wait certificate/wildcard-k8s-ad-gavinf-com --for=condition=Ready --timeout=240s
```

5. check traefik serves it (no `-k`, so curl verifies like a browser does)
```
curl -sS -o /dev/null -w '%{http_code} verify=%{ssl_verify_result}\n' https://hello.k8s.ad.gavinf.com
# 200 verify=0
```

6. turn on the http -> https redirect. only after the cert is good, otherwise every site redirects to
   traefik's self-signed default cert.
```
kubectl apply -f infra/traefik/helmchartconfig.yaml
kubectl -n kube-system rollout status deploy/traefik
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' http://hello.k8s.ad.gavinf.com/
# 301 https://hello.k8s.ad.gavinf.com/
```

### good to know

- certs last 90 days, cert-manager renews ~30 days before expiry. check with
  `kubectl get certificate -n kube-system` (or the dates:
  `kubectl -n kube-system get secret wildcard-k8s-ad-gavinf-com-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates`).
- the wildcard only covers one level: `hello.k8s.ad.gavinf.com` yes, `a.b.k8s.ad.gavinf.com` no.
- apps behind traefik (like argocd with `server.insecure: "true"`) serve plain http inside the cluster;
  traefik terminates tls in front of them.
- a 404 over https means tls worked but no ingress matches that host.
- if a challenge is stuck: `kubectl describe challenge -n kube-system` and
  `kubectl -n cert-manager logs deploy/cert-manager`. "not yet propagated" for more than a few minutes
  usually means the resolver flags are missing or the token can't edit the zone.
