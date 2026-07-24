# Ideas / parking lot

Things that came up while drafting but don't belong in the post being written right now.

---

## part-2-agent-cicd — Scope

**Throughline:** "from laptop demo to team setup" — what changes when you're no longer the one at the terminal?

**Payoff moment (TBD, pick one):**
- (a) Merge a PR and watch the remote agent execute the apply live.
- (b) Out-of-band portal change → drift metric spikes in Grafana → next CI apply fails and you see *why* in the trace. Builds directly on Part 1.

### In scope

- **Formae agent on Azure** — Container Apps vs. ACI (decision open, ACA leaning). Managed Identity for cloud permissions, persistent storage for the Formae DB, VNet-integrated or public+IP-allowlisted.
- **Secrets via Key Vault** — the agent's env (`AZURE_SUBSCRIPTION_ID` etc.) now comes from Key Vault instead of `.env`. Uses the same user-assigned MI pattern from Part 1.
- **CI/CD with GitHub Actions** — OIDC federation between GitHub Actions and Azure (no long-lived secret in the repo). `on: pull_request` → `formae eval`. `on: push` to `main` → `formae apply --mode reconcile`. PR comment with command ID after merge.
- **Observability** — Managed Grafana + Azure Monitor Workspace, chosen because Formae ships pre-built Grafana dashboards (visual payoff). OTel Collector as sidecar in the ACA container. Screenshot of the Formae dashboard after the first CI-triggered apply.

### Chapter outline

1. **Why now?** — recap Part 1's laptop-only scope. Three questions: where does the agent live, who triggers apply, how do you see it work.
2. **The agent moves to the cloud** — ACA + MI + Key Vault + persistent storage.
3. **CI/CD with GitHub Actions** — OIDC federation, PR-eval + main-apply workflow, remote agent API.
4. **Observability** — what Formae emits, OTel Collector wiring, Managed Grafana with pre-built dashboards.
5. **The payoff** — the chosen moment from above, closing the loop with Part 1's drift story.
6. **What Part 2 does not cover** — see "Later parts" below.

### Reference docs

- https://docs.formae.io/en/latest/operations/install-azure/
- https://docs.formae.io/en/latest/formae-101/how-to-guides/cicd-integration/ (Formae's generic CI/CD, not GitHub-Actions-specific — we're on our own for the exact workflow YAML)
- https://docs.formae.io/en/latest/operations/security-networking/
- https://docs.formae.io/en/latest/operations/observability/

### Open questions to resolve before writing

- **ACA vs. ACI** for the agent? ACA gives scaling + health probes with less ops; ACI is simpler and matches the `install-azure` docs more literally.
- **Payoff moment** — (a) live-watching a CI apply, or (b) drift → Grafana → failed apply? (b) is stronger continuity from Part 1.
- **Preview environments per PR** — tempting for CI/CD chapter, but likely inflates scope past a comfortable post length. Punt to Part 4?
- **Migration note**: what happens to the local Formae DB when the agent moves to the cloud? Belongs as a short sidebar in ch. 2, not its own chapter.

---

## Later parts

### Part 2.5 (sidebar): Splitting a stack across teams / lifecycles

A future post (or a "scaling Formae" sidebar) on **when to break one `main.pkl` into multiple stacks**.

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

**To verify before writing:** the exact Pkl syntax for referencing a resource managed by a *different* stack in the same Formae instance (as opposed to a fully unmanaged one). Discovery-based mechanism applies to both, but the accessor shape needs a working example.

### Part 4 candidates

- Preview environments per PR (short-lived Formae stacks tied to PR lifecycle).
- Fine-grained RBAC for the Formae agent across multiple stacks / subscriptions.
- Blue/green or canary deployments with Formae's patch mode.
- Formae + Terraform Cloud/backend interop — extending Part 1's co-existence theme.

### Not planned but worth noting if it comes up

- **Backup/DR for the Formae state** — pure ops question, not a compelling blog story on its own.
- **Multi-region Formae setup** — interesting but niche.
- **Cost management for the observability stack** — worth a one-liner in Part 2 (tear it down when done) but not a chapter.
