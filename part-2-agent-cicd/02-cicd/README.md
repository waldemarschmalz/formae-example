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

**Code-driven change (happy path):**
1. Edit `main.pkl` — change a property, add a tag, whatever.
2. Open a PR. Eval workflow posts a ⚠️ comment showing exactly what will change.
3. Merge. Apply workflow runs → resources updated → done.

**Portal drift (GitOps loop):**
1. Someone edits a managed resource in the Azure Portal.
2. Grafana drift counter ticks (see [`03-observability/`](../03-observability/README.md)).
3. Next merge to `main` → apply pipeline fails with `ReconcileRejected` naming
   the drifted resource.
4. Operator decides:
   - **Absorb** — `formae extract` the drifted resource, merge into `main.pkl`, PR, merge.
   - **Revert** — undo the change in Azure (Portal or `az`), re-run the workflow.
5. Either way ends with PKL and reality re-aligned, and the decision is
   recorded in git.

---

## Workflow design decisions

### GitOps: PKL is the source of truth, humans absorb portal drift

The apply workflow runs `formae apply --mode reconcile --yes` — **no `--force`**.
Portal-side changes to managed resources block the apply with `ReconcileRejected`;
the pipeline fails loudly and points the operator at the resolution path.

Rationale: silently overwriting an out-of-band change on every merge is exactly
the terraform behavior formae was designed to improve on. The agent's
synchronizer notices out-of-band edits precisely so a human can decide whether
they were a mistake (revert them) or an intentional emergency fix (absorb them
into PKL). CI is the wrong place for that decision.

| Situation | Behavior |
|---|---|
| PKL diff, no portal drift | Apply succeeds, resources updated |
| No diff at all | `DriftResolutionRejected` → treated as success, exit 0 |
| Portal drift on managed resource | `ReconcileRejected` → pipeline fails with instructions |

When the pipeline fails on drift, the operator either:
1. **Revert in Azure** (Portal or `az`), then re-run the workflow, or
2. **Absorb into PKL**: `formae extract --query 'stack:… label:…' > drift.pkl`,
   merge into `main.pkl`, open a PR.

### Eval: preview-only, `--simulate --force`

The eval workflow uses `--simulate --force` for the PR drift preview. `--force`
here does not mutate anything — simulate never writes — it only bypasses the
CLI's interactive out-of-band prompt so the run can show what a merge *would*
attempt.

| Simulate result | PR comment |
|---|---|
| `ChangesRequired=true` | ⚠️ shows planned changes |
| `ChangesRequired=false` / no drift | ✅ "No changes required" |
| `stale-review` | ⏳ "Prior review still pending; merge it or wait" |

### About `--resolution`

formae 0.90.0 has a `--resolution` flag intended for non-interactive drift
decisions (JSON payload with `absorb`/`revert` per resource). At the time of
writing it is undocumented and the CLI implementation does not work for the
self-hosted (Classic) profile used here — it returns `Error: unsupported
operation` before contacting the agent. The agent's REST API supports the
mechanism, but wiring CI to raw REST felt like the wrong tradeoff for a demo:
it hides the design intent behind an escape hatch.

The GitOps flow above needs no such flag.

---

## Optional: OIDC for direct Azure access

The workflows above need no Azure credentials — all Azure calls go through the
agent. Add OIDC only if you need to run `az` commands directly in CI (e.g.
for additional validation scripts). See [`scripts/setup-oidc.sh`](scripts/setup-oidc.sh).
