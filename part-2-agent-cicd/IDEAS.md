# Ideas / parking lot

Things that came up while drafting but don't belong in the post being written right now.

---

## part-2-agent-cicd — Scope

**Throughline:** "from laptop demo to team setup" — what changes when you're no longer the one at the terminal?

**Payoff moment: (b) — decided 2026-09-14**
Out-of-band portal change → drift metric spikes in Grafana → next CI apply surfaces the drift in the PR check → developer sees exactly what drifted and why → merge reconciles everything.
Reason: all three chapters are load-bearing. Agent = continuous watcher. CI = surfaces drift to developer. Observability = makes it visible before it's an incident. Closes Part 1's drift story.

### In scope

- **formae agent on Azure** — official `formae-bootstrap` installer, pinned at a commit (VM + agent container + Postgres Flexible Server via private endpoint + VNet/NSG + egress public IP). Access modes: `public` (self-signed, `--allowed-cidr`), `appgw` (App Gateway + Key Vault cert + domain), `tailnet` (private, Tailscale, trusted cert). Agent operates Azure with a scoped SP; creds ride the CustomScript's `protectedSettings` (no VM managed-identity in plugin yet). Replaces the earlier "Container Apps vs. ACI" framing.
- **CI/CD with GitHub Actions** — OIDC federation between GitHub Actions and Azure (no long-lived secret in the repo). `on: pull_request` → `formae eval`. `on: push` to `main` → `formae apply --mode reconcile`. PR comment with command ID after merge.
- **Observability** — Managed Grafana + Azure Monitor Workspace, chosen because formae ships pre-built Grafana dashboards (visual payoff). OTel Collector as sidecar in the ACA container. Screenshot of the formae dashboard after the first CI-triggered apply.

### Chapter outline

1. **Why now?** — recap Part 1's laptop-only scope. Three questions: where does the agent live, who triggers apply, how do you see it work.
2. **The agent moves to the cloud** — VM + Postgres + private endpoint + service principal.
3. **CI/CD with GitHub Actions** — OIDC federation, PR-eval + main-apply workflow, remote agent API.
4. **Observability** — what formae emits, OTel Collector wiring, Managed Grafana with pre-built dashboards.
5. **The payoff** — the chosen moment from above, closing the loop with Part 1's drift story.
6. **What Part 2 does not cover** — see "Later parts" below.

### Reference docs

- https://docs.formae.io/en/latest/operations/install-azure/
- https://docs.formae.io/en/latest/formae-101/how-to-guides/cicd-integration/ (formae's generic CI/CD, not GitHub-Actions-specific — we're on our own for the exact workflow YAML)
- https://docs.formae.io/en/latest/operations/security-networking/
- https://docs.formae.io/en/latest/operations/observability/

### Open questions — resolved 2026-09-14

- **ACA vs. ACI** — ACI. Matches `install-azure` docs literally, less ops for blog post scope.
- **Payoff moment** — (b). See above.
- **Preview environments per PR** — punted to Part 4.
- **Migration note** — sidebar in ch. 2: local formae DB stays local; remote agent gets its own Postgres. No migration needed, stacks are independent.
- **Companion repo** — no vendoring of `formae-bootstrap`. Link + pin commit. Repo adds only: `.github/workflows/`, `03-observability/main.pkl`, READMEs, `scripts/setup-oidc.sh`.

---

## Later parts

### Part 2.5 (sidebar): Splitting a stack across teams / lifecycles

A future post (or a "scaling formae" sidebar) on **when to break one `main.pkl` into multiple stacks**.

The honest criteria are about lifecycle, not size:

- **Different cadence.** Network changes once a quarter; the database gets DDL pushed weekly. Splitting means a database apply can't accidentally touch the VNet.
- **Different ownership.** Platform team owns identity + DNS; app team owns the SQL server and database. Two stacks, two PRs, two destroy commands.
- **Different blast radius.** `formae destroy --query 'stack:app-db'` should not be able to take out the VNet.
- **Reusable foundation.** One `network` stack feeds three different app stacks in the same subscription.

A concrete split of the demo stack along those lines:

```
stacks/
├── network/      # vnet, subnet, dns zone, dns link
├── identity/     # mi, role assignment
└── app-db/       # sql server, database, private endpoint, dns zone group
                  #   references the MI (identity), subnet (network), dns zone (network)
```

`app-db` would reference resources it doesn't own — same Discovery mechanism as the Landing Zone VNet pattern. From `app-db`'s perspective, the MI and subnet are just resources that exist in the world.

**Why not in `01-from-scratch/`:** nine resources, one team, one lifecycle, one reader trying to learn the basics. Splitting would mean three files, three `apply` invocations, and a cross-stack reference pattern to explain before the reader has internalised `.res` within a single stack. Ceremony for its own sake at this stage.

**To verify before writing:** the exact Pkl syntax for referencing a resource managed by a *different* stack in the same formae instance (as opposed to a fully unmanaged one). Discovery-based mechanism applies to both, but the accessor shape needs a working example.

### Part 4 candidates

- Preview environments per PR (short-lived formae stacks tied to PR lifecycle).
- Fine-grained RBAC for the formae agent across multiple stacks / subscriptions.
- Blue/green or canary deployments with formae's patch mode.
- formae + Terraform Cloud/backend interop — extending Part 1's co-existence theme.

### Not planned but worth noting if it comes up

- **Backup/DR for the formae state** — pure ops question, not a compelling blog story on its own.
- **Multi-region formae setup** — interesting but niche.
- **Cost management for the observability stack** — worth a one-liner in Part 2 (tear it down when done) but not a chapter.
