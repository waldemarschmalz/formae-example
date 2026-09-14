# Part 1 · Terraform migrated — put formae in front of the running stack

Assumes [`../02-terraform-original/`](../02-terraform-original/) is already deployed. Nothing gets redeployed here; instead you point formae at the subscription, extract the discovered resources into a Pkl forma, and bring them under management. Then two drift demos — one from the Azure portal, one from Terraform itself — show what formae does when reality diverges from your file.

## What you learn

- How formae **discovers** resources it didn't create.
- How to **adopt** them into a stack with `formae extract` → `formae apply`.
- How **synchronisation** picks up out-of-band changes (portal or Terraform), and how `apply` **refuses** and offers you two options: accept the drift or overwrite it.

## Prerequisites

- [`../02-terraform-original/`](../02-terraform-original/) deployed with defaults (`workload=tf-demo`, `environment=dev`, `instance=001`, `location=westeurope`). If your values differ, adjust the labels/names in `main.pkl` and the queries below to match.
- Local `formae` ≥ `0.87.0`, agent running, Azure plugin installed on the agent:
  ```bash
  sudo formae plugin install azure@0.1.6
  sudo formae agent start
  ```
- `az login` on a subscription where the agent has an Azure Target with `discoverable = true`. Check with:
  ```bash
  formae inventory targets
  ```

## Step 1 — Confirm the resources are discovered

formae's agent scans every target it can reach on a fixed interval (~5 min by default). After `terraform apply` completes in `02-`, it takes one scan tick before the resources appear as `unmanaged`. Then:

```bash
formae inventory resources --query="managed:false label:*tf-demo-dev*"
```

Should show 11 resources (10 you declared in TF plus the network interface that Azure auto-creates for the private endpoint). Two more — the private DNS zone and the role assignment — are also discovered, but don't match the `*tf-demo-dev*` wildcard. That's not a formae quirk; it's Azure naming:

- **Private DNS Zone** — for Private Endpoint to work against Azure SQL, the zone must be named exactly `privatelink.database.windows.net`. The name is fixed by the service, so no `tf-demo-dev` string to match on.
- **Role Assignment** — Azure names role assignments with a random GUID (e.g. `26ed4d89-2633-f4a6-37b6-...`), and formae's discovered label mirrors that GUID.

You'll pick them up separately, by type instead of by label:

```bash
formae inventory resources --query="managed:false type:AZURE::Network::PrivateDnsZone"
formae inventory resources --query="managed:false type:AZURE::Authorization::RoleAssignment"
```

## Step 2 — Extract to Pkl

`formae extract` writes a forma file with the discovered resources. The main batch:

```bash
formae extract --query="managed:false label:*tf-demo-dev*" ./discovered.pkl
```

On a **clean** subscription with only the tf-demo stack you can just run `--query="managed:false"` and get everything in one file. On a busy subscription the wildcard-per-query approach avoids pulling in unrelated resources.

Two things to notice in the extracted file:

**a. The stack is empty** — this is the mechanism to bring things under management:

```pkl
local myStack = new formae.Stack {
  // Please provide a stack to bring the resources in this Forma under management
  // label = ""
  description = "Unmanaged resources"
}
```

Fill in `label = "stack-tf-migration-dev"` before applying. The stack label is what transitions each resource from `unmanaged` to a managed state.

**b. Cross-references are string literals with a warning comment:**

```pkl
new subnet.Subnet {
  ...
  resourceGroupName = "rg-tf-demo-dev-001"      // The target resource with the label = "..." of type = "AZURE::Resources::ResourceGroup" is not managed yet. Bring it under management first to convert this into a Resolvable.
  virtualNetworkName = "vnet-tf-demo-dev-001"   // The target resource with the label = "..." of type = "AZURE::Network::VirtualNetwork" is not managed yet. ...
}
```

That's expected: on first extraction, everything is unmanaged, so formae can't emit `rg.res.name`-style references. After the first apply, re-extracting a resource emits a proper `Resolvable`. Compare with `../01-from-scratch/main.pkl` if you want to see what the `.res.*` reference style looks like when you author from scratch.

## Step 3 — Adopt

Fill in the stack label. Optionally remove the `master` database block if it's present — see the gotcha note at the bottom of this page. Then:

```bash
formae apply --mode reconcile --yes --watch --status-output-layout detailed discovered.pkl
```

`apply` is asynchronous — without `--watch`, it prints a command ID and returns immediately; you'd then run `formae command status --query='id:<that-id>' --output-layout detailed` to see progress. `--watch` blocks until the agent finishes and streams the same output live.

#### About `--mode reconcile` vs `--mode patch`

`--mode` is required on every `apply` — formae won't guess whether you want a full sync or an additive change. The two modes answer different questions:

| Behavior | `reconcile` | `patch` |
|---|---|---|
| Creates the stack if it doesn't exist | Yes | No — fails with `patch can only modify existing stacks` |
| Resource in cloud but not in Pkl | Destroyed | Left alone |
| Collection entry (tag, etc.) in cloud but not in Pkl | Removed | Left alone |
| Refuses if reality drifted since last apply | Yes (override with `--force`) | No — applies over drift; collections are append-only (existing entries preserved) |

**When to reach for `reconcile` — the file is the truth.**
Use it for the first apply (adoption creates the stack), for steady-state applies once you own the stack end-to-end, and any time you want cloud state to converge exactly to Pkl. Cost: it will delete resources and tag entries you removed from the file. Removing a resource block from Pkl is equivalent to `terraform destroy` on that resource. Step 3 above and the `--force` in Step 5's drift override both use this mode.

**When to reach for `patch` — add without removing, even inside collections.**
Use it when other tools or teams also write to the stack's resources and you don't want your apply to strip their additions. Example: a monitoring team's automation writes a `monitoring=enabled` tag onto every RG. Under `--mode reconcile`, if your Pkl doesn't list that tag, it gets stripped on every apply. Under `--mode patch`, the tag survives — patch merges collections append-only, so your entries are added and theirs stay put. Trade-off: `patch` won't create the stack, so it's unusable for the initial adoption in Step 3.

Verify:

```bash
formae inventory resources --query="stack:stack-tf-migration-dev"
```

You'll see **11** resources — the 10 you declared in TF plus the auto-created PE NIC. The DNS zone and the role assignment are still `managed:false` — Step 3b picks them up.

### Step 3b — Adopt the two outliers

First, find the role assignment. `formae inventory` shows all role assignments visible under your target, and each row's `NativeID` column contains the resource group it applies to — scan for the one that mentions `rg-tf-demo-dev-001`:

```bash
formae inventory resources --query="managed:false type:AZURE::Authorization::RoleAssignment" --max-results 50
```

You'll see something like this (abridged):

```
NativeID                                                                                                                       Stack       Type                                    Label
/subscriptions/.../resourceGroups/rg-other-team-01/providers/.../roleAssignments/aaaaaaaa-...                                  unmanaged   AZURE::Authorization::RoleAssignment    aaaaaaaa-...
/subscriptions/.../resourceGroups/rg-tf-demo-dev-001/providers/.../roleAssignments/26ed4d89-2633-f4a6-37b6-0da90c7f5782        unmanaged   AZURE::Authorization::RoleAssignment    26ed4d89-2633-f4a6-37b6-0da90c7f5782   ← this one
/subscriptions/.../resourceGroups/rg-different-thing/providers/.../roleAssignments/cccccccc-...                                unmanaged   AZURE::Authorization::RoleAssignment    cccccccc-...
```

If your subscription only has this one demo, the table will have exactly one row and there's nothing to search for. If it's a shared subscription with lots of RBAC, you'll be filtering through many rows — the row you want is the one whose `NativeID` contains `rg-tf-demo-dev-001`. Copy the `Label` value from that row (it's the same GUID that appears at the end of the `NativeID`).

Then extract both outliers into scratch files. Substitute your GUID into the second command — no angle brackets, no quotes needed:

```bash
formae extract --query="managed:false type:AZURE::Network::PrivateDnsZone" ./dns.pkl
formae extract --query="managed:false label:26ed4d89-2633-f4a6-37b6-0da90c7f5782" ./ra.pkl
```

Copy the `PrivateDnsZone` and `RoleAssignment` blocks from those files into `discovered.pkl` (and add any missing `import` lines at the top). Re-apply with `--watch` again:

```bash
formae apply --mode reconcile --yes --watch --status-output-layout detailed discovered.pkl
```

The output should be something like this:

```bash
apply command with ID 3Fzctnq4mMIElEl3b0Je4u3Oa96: Success (total duration: 3s)
├── update resource 26ed4d89-2633-f4a6-37b6-0da90c7f5782: Success (duration: 2s)
│   ├── of type AZURE::Authorization::RoleAssignment
│   └── from unmanaged to stack-tf-migration-dev
└── update resource privatelink.database.windows.net-3: Success (duration: 3s)
    ├── of type AZURE::Network::PrivateDnsZone
    └── from unmanaged to stack-tf-migration-dev
```

Now `formae inventory resources --query="stack:stack-tf-migration-dev"` shows **13**.

The `main.pkl` shipped in this folder is the end state of steps 2–3b — extract + fill in stack label + drop `master` + append the two outliers. Diff your own extraction against it to see exactly what was cleaned up. (Note: the GUIDs, subscription ID, and tenant ID in the shipped file are from a specific run and won't match yours; use it as a shape reference, not a plug-and-play file.)

## Step 4 — Portal drift

Someone changes a tag from the Azure portal (or via `az`):

```bash
az group update -n rg-tf-demo-dev-001 --tags drift_test=v1 owner=alice
```

Wait for the next sync tick (~5 min), then run apply again:

```bash
formae apply --mode reconcile --yes discovered.pkl
```

formae rejects it:

```
Error: forma rejected because the stacks it references have been modified since the last reconcile command.
There are two options to resolve this issue:
1) use the '--force' flag to apply the forma anyway (this will overwrite any changes made since the last reconcile), or
2) manually adjust your own code:
     - extract the changes made since the last reconcile and incorporate them in your forma before applying it again.
Here is the list of extract commands to use (use different target file names):
formae extract --query='stack:stack-tf-migration-dev type:AZURE::Resources::ResourceGroup label:rg-tf-demo-dev-001-pe-sql-tf-demo-dev-2' <target forma file>
```

Two paths. **Reject the drift** (Pkl wins):

```bash
formae apply --mode reconcile --yes --force --watch --status-output-layout detailed discovered.pkl
```

The `owner=alice` tag disappears from Azure. `az group show -n rg-tf-demo-dev-001 --query tags` reports only `drift_test`.

**Accept the drift** (cloud wins) — run the extract command formae gave you, look at the extracted RG block:

```pkl
new resourcegroup.ResourceGroup {
  ...
  tags = new Listing { new azure.Tag {
      key = "drift_test"
      value = "v1"
    }; new azure.Tag {
      key = "owner"
      value = "alice"
    } }
  ...
}
```

Merge the new `tags` listing into `discovered.pkl`'s RG block and re-apply — formae reconciles happily; Pkl and cloud now agree.

## Step 5 — Terraform drift

Same mechanism, different origin. Edit `../02-terraform-original/main.tf`:

```diff
-  tags = { drift_test = "v1" }
+  tags = { drift_test = "v2" }
```

And apply it via Terraform:

```bash
cd ../02-terraform-original
terraform apply -var=subscription_id=<your-sub-id> -auto-approve
```

Wait for the sync tick, then run apply in `03-`. formae rejects with the same error text as step 4 — from formae's perspective there's no difference between "portal changed it" and "another IaC tool changed it." Reality diverged; Pkl doesn't match. You decide (`--force`, or extract-and-merge).

The docs' phrase for this is [*"happily co-exist"*](https://github.com/platform-engineering-labs/formae). It doesn't mean formae ignores Terraform — it means both tools observe the same cloud, and formae surfaces the divergence for you to resolve on your terms.

## What's next

- Part 2 covers the remote agent (running on ACI instead of localhost), Azure DevOps CI/CD, and Key Vault-backed secrets — the pieces that turn this from a laptop demo into a shared team workflow.

## Gotchas worth knowing

- **Adoption cannot be `patch`.** Patch mode requires the stack to exist. The first adoption apply must be `reconcile` — it creates the stack.
- **The `master` database.** Azure auto-creates it under every SQL logical server. `formae extract` emits a block for it. Adopting it is fine, but the moment you `reconcile` a version of the file that no longer contains it, formae will try to delete it and Azure will refuse with `CannotUseReservedDatabaseName: Cannot use reserved database name 'master' in this operation.` — the server itself is unaffected, but the apply fails. Simpler to leave it out of the file from the start and accept that `formae inventory resources --query="managed:false"` will always list it. Verified: `az sql db delete -n master ...` returns the same error, so this is Azure's behavior, not formae's.
- **Labels aren't identity.** formae's `label` on discovered resources is a human-readable slug that may pick up `-2` suffixes when there's a name collision with a prior stale record. Adoption matching uses the Azure resource ID (`name` + parent scope + subscription), not the label. Leave the discovered labels as-is; renaming them post-adoption is a separate operation.
- **Sync interval matters.** The 5-minute default is fine for demos; production stacks that need faster drift-detection can shorten it in the agent config. `formae apply` doesn't force a scan — it reads the last-known state and compares against your file.
