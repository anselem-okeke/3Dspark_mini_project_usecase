## Oauth2-OIDC Architecure
![Alt text for the image](img/demoapp.gif)
![Alt text for the image](img/oauth_arch.svg)

---

## One-click install (Linux)
This demo deploys a complete stack in one command:
- Local kind Kubernetes cluster 
- NGINX Ingress Controller 
- Keycloak + Postgres 
- oauth2-proxy protecting the demo app 
- Optional observability (Prometheus/Grafana) depending on .env

### Prerequisites (Ubuntu/Debian)

- Linux machine (tested on Ubuntu/Debian)
- Internet access (to pull container images + download CLI tools)
- make installed (sudo apt-get install -y make if missing)

---

### Quick start (one command)
```shell
git clone <repo-url>
cd <repo-folder>

cp .env.example .env 2>/dev/null || true
# Edit .env if you want different IP/hosts
# BASE_DOMAIN should point to your VM/host IP using nip.io
# Example: BASE_DOMAIN=192.168.56.11.nip.io

make up
```
### What `make up` does:
- Ensures required tooling exists (auto-installs on Ubuntu/Debian if missing)
- Creates the kind cluster 
- Installs ingress + apps 
- Runs a health check
### Access the apps
- After `make up`, you should see output like:
- Keycloak: http://keycloak.<BASE_DOMAIN>
- Demo App (protected): http://demo.<BASE_DOMAIN>
### Example (from the default VM setup):
- `http://keycloak.192.168.56.11.nip.io`
- `http://demo.192.168.56.11.nip.io`

### Login credentials
- Demo user is created automatically by the Keycloak bootstrap job.
```shell
kubectl -n spark get secret spark-demo-user -o jsonpath='{.data.username}' | base64 -d; echo
kubectl -n spark get secret spark-demo-user -o jsonpath='{.data.password}' | base64 -d; echo
```
### Useful commands
```shell
make redeploy
make down
```

## Login guide (step-by-step)
- This project exposes two public URLs (via Ingress):
  - Keycloak (login page): http://keycloak.<BASE_DOMAIN>
  - Demo app (protected): http://demo.<BASE_DOMAIN>
  - <BASE_DOMAIN> is `host IP` + `.nip.io` (example: 192.168.56.11.nip.io)

1) Start the stack 
- From the repo root:
```shell
make up
```
- Wait until it finishes and prints the URLs.

2) Confirm the demo user exists

- The bootstrap job creates a demo user and stores the credentials in a Kubernetes secret.

```shell
kubectl -n spark get secret spark-demo-user -o jsonpath='{.data.username}' | base64 -d; echo
kubectl -n spark get secret spark-demo-user -o jsonpath='{.data.password}' | base64 -d; echo
```
- Default demo credentials (unless you changed .env) are:
  - `username: alice` 
  - `password: Password123!`

3) Open the protected demo app

- Open in your browser:
  - `http://demo.<BASE_DOMAIN>`

- What you should see:
  - You will not see the app immediately. 
  - You will be redirected to Keycloak for login.

4) Log in on Keycloak
- You’ll land on the Keycloak login page at:
  - `http://keycloak.<BASE_DOMAIN>`
  - Log in using the demo credentials from step 2.

5) What happens after login

- After successful login:
  - Keycloak redirects you back to:
  http://demo.<BASE_DOMAIN>/oauth2/callback

Then:
- oauth2-proxy exchanges the login code for tokens (inside the cluster)
- oauth2-proxy sets an auth cookie for `.<BASE_DOMAIN>`
- you are redirected back to: `http://demo.<BASE_DOMAIN>/`
- the request is now authenticated and oauth2-proxy forwards you to the demo app upstream 
- You should now see the demo app page.

**If something goes wrong**

A) You see an oauth2-proxy error page

- Check oauth2-proxy logs:
```shell
kubectl -n spark logs deploy/oauth2-proxy --tail=200
```
- Common cause we fixed in this design:
  - email not verified → Keycloak user must have emailVerified=true (handled by bootstrap)

B) You can reach Keycloak but demo redirects/loops

- Confirm oauth2-proxy is using the correct public URLs:

```shell
kubectl -n spark get deploy oauth2-proxy -o jsonpath='{.spec.template.spec.containers[0].args}' \
| tr ',' '\n' | egrep 'issuer|redirect|login|redeem|jwks'
```


- You should see (no ports, public hostnames):
  - `--oidc-issuer-url=http://keycloak.<BASE_DOMAIN>/realms/<REALM>`
  - `--redirect-url=http://demo.<BASE_DOMAIN>/oauth2/callback`
  - `--login-url=http://keycloak.<BASE_DOMAIN>/realms/<REALM>/protocol/openid-connect/auth`

- And internal backchannel URLs:
  - `--redeem-url=http://keycloak.<NAMESPACE>.svc.cluster.local/.../token`
  - `--oidc-jwks-url=http://keycloak.<NAMESPACE>.svc.cluster.local/.../certs`

C) Quick health checks (no browser)
```shell
# Keycloak should respond via Ingress
curl -I -H "Host: keycloak.${BASE_DOMAIN}" http://127.0.0.1/ | head

# Demo should redirect into the auth flow
curl -I -H "Host: demo.${BASE_DOMAIN}" http://127.0.0.1/ | head
```


- Keycloak often returns 302 (redirect to /admin/) → that’s fine

- Demo returns 302 (redirect into oauth2 flow) → that’s expected

### Stop everything
```shell
make down
```
- That removes the app resources and deletes the kind cluster.

## Troubleshooting and What I fixed (full reference)
This part captures the real issues I hit while building this one-click Kind + Ingress + Keycloak + oauth2-proxy demo,
why they happened, and the exact fixes that made the system stable. It is meant to be a single source of truth for anyone 
running this project later.

---

1) What the project is doing
- Public URLs (from your browser)
  - Demo app (protected): `http://demo.<BASE_DOMAIN>`
  - Keycloak: `http://keycloak.<BASE_DOMAIN>`

- `<BASE_DOMAIN>` uses `nip.io`, so it resolves automatically:
  - Example: `BASE_DOMAIN=192.168.56.11.nip.io`

- Then:
  - `demo.192.168.56.11.nip.io → 192.168.56.11` 
  - `keycloak.192.168.56.11.nip.io → 192.168.56.11`

- What’s actually behind those URLs 
  - Traffic flow is:
    - Browser hits demo.<BASE_DOMAIN>
    - Ingress routes demo host → oauth2-proxy 
    - oauth2-proxy redirects browser to Keycloak login (public URL)
    - Keycloak returns the browser to demo.<BASE_DOMAIN>/oauth2/callback 
    - oauth2-proxy exchanges the code for tokens (internal cluster call)
    - oauth2-proxy forwards to the demo upstream (demo-app.<namespace>.svc.cluster.local)

  - Key idea: Browser uses public FQDNs. Cluster uses internal service DNS. 
    - That boundary is where most issues came from.

2) The “stable configuration rules” (the core lessons)

- These are the rules that ended the “it worked earlier / now it broke” cycle:
  - Rule A — Never mix “public port mapping” with “internal cluster routing” 
    - Browser-facing URLs must be reachable from your laptop. 
    - Backchannel token/JWKS calls must use Kubernetes service DNS (*.svc.cluster.local).

  - So oauth2-proxy must be configured like this:
    - Public (browser)
      - --oidc-issuer-url=http://keycloak.<BASE_DOMAIN>/realms/<REALM>
      - --login-url=http://keycloak.<BASE_DOMAIN>/realms/<REALM>/protocol/openid-connect/auth 
      - --redirect-url=http://demo.<BASE_DOMAIN>/oauth2/callback
    - Internal (cluster)
      - --redeem-url=http://keycloak.<NAMESPACE>.svc.cluster.local/realms/<REALM>/protocol/openid-connect/token 
      - --oidc-jwks-url=http://keycloak.<NAMESPACE>.svc.cluster.local/realms/<REALM>/protocol/openid-connect/certs 
      - This removed the “sometimes Keycloak works, sometimes callback fails” instability.

  - Rule B — Don’t rely on OIDC discovery when public/internal differ 
    - I hit issues when discovery returned public URLs but oauth2-proxy needed internal ones for redeem/jwks. 
    - Fix:
      - --skip-oidc-discovery=true 
      - Provide --login-url, --redeem-url, --oidc-jwks-url explicitly.

  - Rule C — One port strategy only (avoid shadow ports)
    - I had instability when sometimes URLs used :18080 and sometimes not. 
    - Stable setup: publish the Ingress controller on port 80/443 only, and do not include ports in URLs. 
    - That means:
      - Browser URLs are clean: http://demo.<BASE_DOMAIN> and http://keycloak.<BASE_DOMAIN>
      - No :18080 anywhere in oauth2-proxy args

3) Major problems I faced (and how I solved them)
- Problem 1 — Kind cluster fails to start: “address already in use” 
  - Symptom:
    - kind create cluster fails with something like:
      - failed to bind host port for 0.0.0.0:80 ... address already in use

  - Root cause:
    - Some service on the VM host already occupies port 80/443 (often Nginx, Apache, Caddy, etc.).

  - Fix:
    - Stop the conflicting service OR change kind port mapping.
    - I decided the stable solution for this project is:
      - Use 80 → 30080 and 443 → 30443 in scripts/kind-up.sh

  - Then confirm:
```shell
docker ps --format 'table {{.Names}}\t{{.Ports}}' | grep spark-mvp-control-plane
```



- You should see:

  - `0.0.0.0:80->30080/tcp`

  - `0.0.0.0:443->30443/tcp`

- Problem 2 — Keycloak works, but oauth2-proxy redirect fails / times out

  - Symptoms I saw:
    - Keycloak UI loads, but oauth2 login redirect leads to timeout or “can’t reach page” 
    - Sometimes keycloak.<BASE_DOMAIN> works but keycloak.<BASE_DOMAIN>:18080 fails

  - Root cause:
    - I was mixing port assumptions:
      - Kind was publishing 80/443, but oauth2-proxy or scripts used :18080. 
      - That created a “working sometimes” setup depending on which URL the browser was redirected to.

  - Fix:
  - Stop using PUBLIC_PORT in URLs for browser flows. 
  - Use plain:
    - http://keycloak.<BASE_DOMAIN>
    - http://demo.<BASE_DOMAIN>
    - If you still keep PUBLIC_PORT in the repo, keep it only for alternate setups, but the stable reference is no port.

- Problem 3 — Ingress returns 404 / 403 randomly

  - Symptoms:
    - curl -H "Host: demo.<BASE_DOMAIN>" http://127.0.0.1/ returns 404 
    - or returns 403 even though pods are running

  - Root causes (I hit both):
    - Host mismatch (ingress exists but the Host header doesn’t match)
    - .env not loaded in your shell, so commands used literal ${BASE_DOMAIN}

  - Fix:
    - Always load .env when debugging locally:
```shell
set -a; source .env; set +a
```
- Then test correctly using the Host header:
```shell
curl -I http://127.0.0.1/ -H "Host: keycloak.${BASE_DOMAIN}" | head
curl -I http://127.0.0.1/ -H "Host: demo.${BASE_DOMAIN}"    | head
```
- Expected:
  - Keycloak typically: 302 (redirects to /admin/)
  - Demo: 302 (redirects into oauth2-proxy flow)

- Also verify ingresses:
```shell
kubectl -n spark get ingress -o wide
```


- Problem 4 — The browser suddenly resolves wrong host like http://oauth2/...

  - Symptom:
    - Browser shows URL like http://oauth2/start?... and fails with DNS NXDOMAIN.

  - Root cause:
    - Ingress misrouting or a broken redirect URL produced a relative redirect without a proper host, or an incorrect host got into redirects.

  - Fix:
    - Ensure oauth2-proxy args are correct and stable:
      - --redirect-url=http://demo.<BASE_DOMAIN>/oauth2/callback 
      - --oidc-issuer-url=http://keycloak.<BASE_DOMAIN>/realms/<REALM>
      - --login-url=http://keycloak.<BASE_DOMAIN>/realms/<REALM>/protocol/openid-connect/auth 
      - --reverse-proxy=true 
      - cookie + whitelist domain set to the BASE_DOMAIN

  - Sanity check:
```shell
kubectl -n spark get deploy oauth2-proxy -o jsonpath='{.spec.template.spec.containers[0].args}' \
| tr ',' '\n' | egrep 'issuer|redirect|login|redeem|jwks|cookie-domain|whitelist-domain|reverse-proxy'
```
- Problem 5 — Login completes but callback returns 500

  - Symptom:
    - After logging in, browser shows 500 Internal Server Error on /oauth2/callback.

  - The key evidence was in logs:
    - Error redeeming code during OAuth2 callback: email in id_token (...) isn't verified

  - Root cause:
    - oauth2-proxy (depending on config/provider expectations) may require verified email. demo user was created without emailVerified=true, so Keycloak issued a token where the email is not verified.
    - in future, login step may require different levels of authentication.
    
    - Fix (final and correct):
      - In the Keycloak bootstrap job:
        - Set a demo email 
        - Mark it verified 
        - Ensure requiredActions are empty so Keycloak doesn’t force profile updates

    - Where to add it:
      - Right after you have USER_ID (after create-or-fetch), add:

```shell
EMAIL="${DEMO_USER}@example.com"

# If user is being created, include email fields in the POST.
# If user already exists, enforce via PUT.

curl -fsS -H "${AUTHZ}" -H "Content-Type: application/json" \
  -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/users/${USER_ID}" \
  -d "{\"email\":\"${EMAIL}\",\"emailVerified\":true,\"requiredActions\":[]}" >/dev/null
```

- This is what finally made the end-to-end OAuth flow stable.

- Problem 6 — Keycloak hostname variables caused broken redirects

  - Symptom:
    - Keycloak sometimes worked, but redirects/callbacks didn’t match the URL you typed (or started bouncing).

  - Root cause:
    - I experimented with Keycloak hostname variables such as KC_HOSTNAME_URL.
    When combined with ingress reverse proxy headers, it can lead to mismatched issuer/hostnames or unexpected behavior.

  - Fix:
    - Keep Keycloak proxy settings minimal and consistent for this demo.
    Use what we settled on (example pattern):
      - KC_PROXY=edge 
      - KC_PROXY_HEADERS=xforwarded 
      - KC_HOSTNAME_STRICT=false 
      - and avoid KC_HOSTNAME_URL unless you really need it.

4) How to verify each layer (debug checklist)

- Run these in order. Don’t skip layers.

- Layer 1 — Ports
```shell
docker ps --format 'table {{.Names}}\t{{.Ports}}' | grep spark-mvp-control-plane
```


- Confirm host ports (80/443) are published.

- Layer 2 — Ingress controller ready
```shell
kubectl -n ingress-nginx get pods
kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller
```

- Layer 3 — Ingress objects exist and hosts match
```shell
kubectl -n spark get ingress -o wide
```

- Layer 4 — Ingress routes respond locally (Host header test)
```shell
set -a; source .env; set +a
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: keycloak.${BASE_DOMAIN}" http://127.0.0.1/
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: demo.${BASE_DOMAIN}"    http://127.0.0.1/
```


- Layer 5 — Keycloak issuer consistency
```shell
curl -s -H "Host: keycloak.${BASE_DOMAIN}" \
  "http://127.0.0.1/realms/${KEYCLOAK_REALM}/.well-known/openid-configuration" | jq -r .issuer
```
- Expected:
  - http://keycloak.<BASE_DOMAIN>/realms/<REALM>

Layer 6 — oauth2-proxy health & logs
```shell
kubectl -n spark logs deploy/oauth2-proxy --tail=200
```
- If callback fails, the root cause is almost always in these logs.

- Layer 7 — Bootstrap job completed successfully
```shell
kubectl -n spark get jobs
kubectl -n spark logs job/keycloak-bootstrap --tail=200
```

5) “One-click” stability: why I use scripts and Makefile

- I ended up with this one-click lifecycle:
  - make up → creates kind cluster, installs everything, verifies health 
  - make down → removes app resources + deletes kind cluster 
  - make redeploy → rebuilds manifests in-place

- Makefile already orchestrates correctly:

```yaml
up: kind-up install health
down: uninstall kind-down
redeploy: uninstall install health
```


- The last missing piece was dependency onboarding, so new users don’t need to manually install tools.

  - That’s why I added:
    - scripts/check-deps.sh 
    - scripts/deps-ubuntu.sh 
    - make deps-ubuntu

  - So the user story becomes:
    - make deps-ubuntu 
    - make up

6) What changed over time (so you don’t regress)

- These are the changes that mattered most (don’t undo them casually):
  - Standardized on port 80/443 for the Ingress entrypoint (no more :18080 URLs)
    - oauth2-proxy now uses:
      - public issuer/login/redirect URLs (browser reachable)
      - internal redeem/jwks URLs (cluster DNS)
      - --skip-oidc-discovery=true 
      - --reverse-proxy=true 
      - cookie/whitelist domains for .<BASE_DOMAIN>

    - Bootstrap job now:
      - enforces client redirectUris/webOrigins (PUT)
      - creates user with email + emailVerified=true 
      - avoids required actions that can trigger forced profile updates 
      - Keycloak hostname settings kept minimal to avoid issuer/redirect mismatch

7) If you want the “fast reset” button

- When things get weird and you want a clean slate:

```yaml
make down
make up
```


- If docker ports are still stuck (rare), ensure nothing else is binding 80/443.

- End result (what “working” looks like)

  - ✅ `http://keycloak.<BASE_DOMAIN>` loads Keycloak UI
  - ✅ `http://demo.<BASE_DOMAIN>` redirects to login
  - ✅ After login, you return to demo and the app is visible
  - ✅ oauth2-proxy logs show no “email not verified” errors
  - ✅ bootstrap job completes successfully every time



