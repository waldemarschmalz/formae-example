# 02 · CI/CD with GitHub Actions

Deploys the [Part 1 "from scratch" forma](main.pkl)
(Azure SQL + Private Endpoint stack) via the remote formae agent.
No long-lived Azure credentials in the repo — the agent holds the SP; CI only
needs the agent password and Tailscale access.

| Trigger | Job | Agent contact |
|---------|-----|---------------|
| `pull_request` | `formae eval` (PKL validation) + `--simulate` (drift preview) | simulate only |
| `push` to `main` | `formae apply --mode reconcile` + poll until terminal state | yes |

## How it works

```
GitHub Actions runner
  │
  ├─ joins Tailscale (tag:ci)
  │
  └─ formae CLI ──── bootstrap profile ────► formae agent (tag:formae, ts.net)
                                                      │
                                                      └─► Azure (SP creds on agent)
```

The runner never holds Azure credentials. The remote agent authenticates to
Azure using the service principal configured at bootstrap time.

---

## 1 · Tailscale setup

The CI runner joins the tailnet as an ephemeral node (`tag:ci`). Two things to
configure in the [Tailscale admin console](https://login.tailscale.com/admin).

**a) ACL — allow CI to reach the agent:**

Both `tag:ci` and `tag:formae` must exist in `tagOwners`
([Admin → Access Controls](https://login.tailscale.com/admin/acls)).
The current wildcard grant (`src:* dst:* ip:*`) already covers this — no
change needed. If you ever remove the wildcard, add a specific grant:

```json
{ "src": ["tag:ci"], "dst": ["tag:formae"], "ip": ["49684"] }
```

**b) OAuth client for GitHub Actions:**

[Admin → Settings → Trust credentials](https://login.tailscale.com/admin/settings/trust-credentials)
→ **Credential → OAuth**:
- Scope: **`auth_keys: Write`** (required by `tailscale/github-action`)
- No tag restriction needed here — the tag is set in the workflow via `tags: tag:ci`

Click **Generate credential**. Copy the **client ID** and **secret** — shown
once, store them immediately as GitHub secrets.

---

## 2 · GitHub secrets

Go to **Settings → Secrets and variables → Actions → New repository secret**
and add all five:

| Secret | Value | Where to find it |
|--------|-------|-----------------|
| `TS_OAUTH_CLIENT_ID` | Tailscale OAuth client ID | Tailscale admin → OAuth clients |
| `TS_OAUTH_SECRET` | Tailscale OAuth secret | same |
| `FORMAE_AGENT_FQDN` | `formae-bootstrap.<tailnet>.ts.net` | profile URL in `~/.config/formae/profiles/bootstrap.pkl` |
| `FORMAE_API_PASSWORD` | plain-text agent API password | output of `gen-api-credential.sh` at bootstrap time |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID | `az account show --query id -o tsv` |

---

## 3 · Workflow files

- [`.github/workflows/formae-eval.yml`](../../.github/workflows/formae-eval.yml) — PR check
- [`.github/workflows/formae-apply.yml`](../../.github/workflows/formae-apply.yml) — apply on merge

Both workflows generate the bootstrap profile at runtime from secrets — nothing
sensitive is checked into the repo.

---

## Payoff demo

1. Stack is deployed (first apply via CI or local `formae apply`).
2. Make an out-of-band change in the Azure Portal (e.g. change the SQL Server
   `minimalTlsVersion` or add a tag to the resource group).
3. Open any PR — the `--simulate` step shows the drift: which property,
   old vs. new value.
4. Merge the PR; `formae apply --mode reconcile` corrects the drift.
5. The drift counter ticks in Grafana (see [`03-observability/`](../03-observability/README.md)).

---

## Workflow design decisions

### Apply: no re-simulate, straight `--force`

The apply workflow runs `formae apply --mode reconcile --force --yes` directly —
it does **not** re-simulate before applying. Two reasons:

1. **stale-review conflict** — the PR eval already created a review on the agent.
   Re-simulating in the apply job conflicts with that review and returns
   `DriftResolutionRejected/stale-review`, blocking the apply.
2. **`--force` makes the review unnecessary** — it tells the agent to bypass the
   review gate and apply current declared state unconditionally.

Only two outcomes handled in the apply step:
- `DriftResolutionRejected` → no changes, exit 0 (not a failure)
- Anything else non-zero → real failure, fail loud with raw output

### Eval: stale-review = hard fail, not a silent swallow

If the eval workflow returns `stale-review` (a prior review from an earlier eval
run is still pending on the agent), the step fails with a clear message rather
than swallowing it. This happens when the eval is re-triggered multiple times
without an apply in between consuming the pending review.

Fix: merge to apply (which clears the review), then re-run the eval if needed.

### `--force` and out-of-band changes

`--force` on the simulate step (`--force --simulate`) surfaces out-of-band
changes (normally blocked as `ReconcileRejected` by the agent's synchronizer)
so they appear as drift in the PR comment. Without `--force`, the synchronizer's
pending observation would block the simulate entirely.

`--force` on the real apply reverts those out-of-band changes to match declared
state. The PR review is the human gate — merging is the explicit approval.

---

## Optional: OIDC for direct Azure access

The workflows above need no Azure credentials — all Azure calls go through the
agent. Add OIDC only if you need to run `az` commands directly in CI (e.g.
for additional validation scripts). See [`scripts/setup-oidc.sh`](scripts/setup-oidc.sh).
