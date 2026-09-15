# Part 2 · Agent + CI/CD + Observability

From laptop demo to team setup: where the agent lives, who triggers apply, and
how you see it work.

## Contents

- `01-remote-agent/` — explains how to stand up the remote agent (VM + PostgreSQL +
  private network) using formae's official `formae-bootstrap` installer, pinned
  to a specific commit — no vendored code. [Start here.](01-remote-agent/README.md)
- (planned) `cicd/` — GitHub Actions with OIDC federation: `on: pull_request` →
  `formae eval`, `on: push` to `main` → `formae apply --mode reconcile`.
- (planned) `observability/` — Managed Grafana + Azure Monitor workspace, OTel
  sidecar, pre-built formae dashboards.

See `IDEAS.md` for the scope and open questions (ACA vs. ACI, payoff moment,
preview environments).

---

## What the agent costs on Azure

Default `small` install (`public` mode), pay-as-you-go, `westeurope`, mid-2026
list prices. The exact resource set is formae's official `bootstrap.pkl`; this
table is the running-cost counterpart to Part 1's ~€12/mo SQL stack.

| Resource | Detail | Unit | Monthly (744 h) |
| -------- | ------ | ---- | --------------- |
| VM `Standard_D2s_v6` | 2 vCPU / 8 GB, `small` | €0.121 / h | **€90.02** |
| VM OS disk | `StandardSSD_LRS`, 30 GB → billed as 128 GB (E10) | €9.60 + €1.18 / mo | **€10.78** |
| PostgreSQL Flexible Server `B1ms` | 1 vCPU / 2 GB, burstable | €0.0199 / h | **€14.81** |
| PostgreSQL storage | 32 GiB General Purpose | €0.137 / GiB | **€4.38** |
| PostgreSQL backups | LRS, above the free allotment | €0.119 / GB | ~€0–4 |
| Private Endpoint | to Postgres (part-1 anchor) | | **€6.92** |
| Private DNS zone | 1 zone + link | | **€0.60** |
| Public IP (Standard, static) | egress, all modes | €0.005 / h | **€3.72** |
| **Total — `public` / `tailnet`** | | | **≈ €131 / mo** |

**`appgw` mode adds** (public HTTPS via Application Gateway + Key Vault cert):

| Resource | Detail | Unit | Monthly |
| -------- | ------ | ---- | ------- |
| Application Gateway v2 | 1 capacity unit, Standard_v2 | ~€0.0127 / unit-h | **≈ €49** |
| Gateway public IP | Standard, static | €0.005 / h | **€3.72** |
| Key Vault (standard) | certificate storage | ~free at this load | €0 |
| App GW subnet + UAMI | | | €0 |
| **`appgw` incremental** | | | **≈ + €53 / mo** |

### Caveats

- **Prices drift.** These are mid-2026 retail list rates, USD-converted;
  reservations, Azure credits, and regional offers cut them. Verify against the
  Azure Pricing Calculator before committing the number to a post.
- **VM disk is billed one tier up.** A 30 GB OS disk isn't a standard size, so
  Azure bills the next tier (E10, 128 GB) — hence €10.78, not ~€2.
- **`B1ms` is burstable.** The €0.0199/h burn-down covers overage on top of the
  included 744 h/mo burst credits; an idle agent with small state idles cheaper
  in practice.
- **`tailnet` costs the same as `public`.** The VM still needs the public IP for
  egress (Azure retired default outbound access); there's just no inbound NSG
  rule and no App Gateway.
- **`medium` is the same price** as `small` (same `Standard_D2s_v6`); `large`
  (`Standard_D4s_v6`, €0.242/h) adds ~+€90/mo.

### Bottom line

Docs-default `public` mode runs **≈ €131/month** continuously. `appgw` ≈
**€184/month**. Tear down with
`formae destroy --query "stack:formae-bootstrap-azure"` when you're done.

---

## Where to go next

Start with [`01-remote-agent/`](01-remote-agent/README.md) to stand the agent up, then wire
CI/CD and observability (planned).