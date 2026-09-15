# Part 2 · Work Plan (Sept 14–17)

---

## Day 1 · Sept 14 — Deploy the remote agent

### Goal: `formae agent status --profile bootstrap` is green.

- [ ] Clone formae-bootstrap at pinned commit
  ```bash
  git clone https://github.com/platform-engineering-labs/formae-bootstrap.git
  cd formae-bootstrap
  git checkout 1eeebab2e3f8336e09d14ec2a3a07efacafc0bd7
  ```

- [ ] Generate API credential hash
  ```bash
  azure/scripts/gen-api-credential.sh
  # saves: API_PASSWORD and API_PASSWORD_HASH
  ```

- [ ] Prep variables (fill in your values)
  ```bash
  LOCATION=westeurope
  SUBSCRIPTION_ID=<your-sub>
  TENANT_ID=<your-tenant>
  SP_APP_ID=<service-principal-appid>
  SP_SECRET=<service-principal-password>
  API_PASSWORD_HASH=<from gen-api-credential.sh>
  DB_PASSWORD=<choose a strong password>
  SSH_PUB=$(cat ~/.ssh/id_ed25519.pub)
  ```

- [ ] Deploy agent infra
  ```bash
  formae apply --mode reconcile azure/bootstrap.pkl \
    --access public \
    --location $LOCATION \
    --subscription-id $SUBSCRIPTION_ID \
    --tenant-id $TENANT_ID \
    --client-id $SP_APP_ID \
    --client-secret "$SP_SECRET" \
    --api-password-hash "$API_PASSWORD_HASH" \
    --db-password "$DB_PASSWORD" \
    --ssh-public-key "$SSH_PUB" \
    --status-output-layout detailed \
    --yes
  ```
  Takes ~10–15 min. Watch for errors.

- [ ] Verify health
  ```bash
  curl -k https://formae-bootstrap.$LOCATION.cloudapp.azure.com:49684/api/v1/health
  ```

- [ ] Write bootstrap profile
  ```bash
  azure/scripts/write-bootstrap-profile.sh \
    --profile bootstrap \
    --access public \
    --fqdn formae-bootstrap.$LOCATION.cloudapp.azure.com \
    --user formae \
    --password "$API_PASSWORD"
  ```

- [ ] Confirm agent status
  ```bash
  formae agent status --profile bootstrap
  ```

- [ ] Run one apply against remote agent (smoke test)
  ```bash
  formae apply --mode reconcile part-1-intro/01-from-scratch/main.pkl \
    --profile bootstrap --status-output-layout detailed
  ```

- [ ] Note any gaps in `01-remote-agent/README.md` and fix them

---

## Day 2 · Sept 15 — CI/CD with GitHub Actions

### Goal: PR triggers eval, push to main triggers apply. Both green.

- [ ] Set up OIDC federation
  ```bash
  cd part-2-agent-cicd/02-cicd
  ./scripts/setup-oidc.sh \
    --repo <your-org/formae-example> \
    --subscription $SUBSCRIPTION_ID
  ```

- [ ] Add 4 secrets to GitHub repo (Settings → Secrets → Actions)
  - `AZURE_CLIENT_ID`
  - `AZURE_TENANT_ID`
  - `AZURE_SUBSCRIPTION_ID`
  - `FORMAE_API_PASSWORD`

- [ ] Write `.github/workflows/formae-eval.yml`
  - Trigger: `pull_request`
  - Steps: `az login` (OIDC), install formae CLI, configure remote profile, `formae eval`

- [ ] Write `.github/workflows/formae-apply.yml`
  - Trigger: `push` to `main`
  - Steps: same login, `formae apply --mode reconcile`, post command ID as PR comment

- [ ] Open a test PR with a trivial stack change — confirm eval runs and passes

- [ ] Merge the test PR — confirm apply runs against remote agent, stack changes in Azure

- [ ] Take screenshot: GitHub Actions log showing apply output + command ID comment on PR

- [ ] Write/finalize `02-cicd/README.md` based on what actually worked

---

## Day 3 · Sept 16 — Observability + the payoff demo

### Goal: Grafana live. Drift demo staged and screenshot.

- [ ] Check formae observability docs for exact Azure Monitor + Managed Grafana resource types
  - https://docs.formae.io/en/latest/operations/observability/

- [ ] Write `03-observability/main.pkl`
  - Azure Monitor Workspace
  - Azure Managed Grafana (Essential tier, link to workspace)

- [ ] Deploy observability stack
  ```bash
  formae apply --mode reconcile 03-observability/main.pkl \
    --location westeurope \
    --grafana-admin-email you@example.com \
    --profile bootstrap --status-output-layout detailed
  ```

- [ ] Wire OTel Collector sidecar to agent (per formae docs)

- [ ] Open Grafana, confirm pre-built formae dashboards load

- [ ] **Stage the payoff demo**
  1. Confirm stack deployed and metrics flowing in Grafana
  2. Open Azure Portal, manually change a property on a managed resource (e.g. modify a tag)
  3. Watch drift metric tick in Grafana — screenshot this
  4. Open a PR with any change
  5. Watch `formae eval` in CI surface the drift — screenshot the check output
  6. Merge the PR
  7. Watch `formae apply --mode reconcile` correct the drift — screenshot apply log
  8. Confirm Grafana shows drift resolved

- [ ] Collect all screenshots (Grafana spike, CI eval output, apply log, Grafana resolved)

- [ ] Write/finalize `03-observability/README.md`

---

## Day 3.5 · Sept 17 (half day) — Blog post draft

### Goal: Full draft written, ready for editing/review.

Chapter structure (from IDEAS.md):

- [ ] **Intro / Why now?** — recap Part 1's laptop-only setup; three questions: where does the agent live, who triggers apply, how do you see it work

- [ ] **Ch. 2 — The agent moves to the cloud** — formae-bootstrap walkthrough, access modes, cost table, short sidebar: local formae DB stays local, no migration needed

- [ ] **Ch. 3 — CI/CD with GitHub Actions** — OIDC federation (why no secrets), PR eval, push apply, PR comment with command ID, screenshot

- [ ] **Ch. 4 — Observability** — what formae emits, OTel wiring, Managed Grafana dashboards, screenshot

- [ ] **Ch. 5 — The payoff** — the full drift demo sequence using your screenshots; close the loop with Part 1

- [ ] **Ch. 6 — What Part 2 does not cover** — preview environments, multi-team RBAC, blue/green (Part 4 candidates)

- [ ] Check all companion repo links and CLI commands in the draft match what actually ran

---

## Carry-forward blockers

| Blocker | Blocks |
|---------|--------|
| Agent not running | Everything on Day 2 and Day 3 |
| OIDC not set up | Day 2 workflow testing |
| Observability not wired | Day 3 payoff demo |
