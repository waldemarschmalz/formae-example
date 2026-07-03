# Part 1 · From scratch — Azure SQL behind a Private Endpoint

A nine-resource Formae stack that deploys an Azure SQL Server locked down to a private network, with a User-Assigned Managed Identity as its **only** admin. No passwords anywhere.

## What gets deployed

- **Resource Group**
- **User-Assigned Managed Identity** — the SQL server's Entra-only admin
- **Role Assignment** — MI gets `Reader` on the resource group
- **Azure SQL Server** — `azureADOnlyAuthentication = true`, `publicNetworkAccess = "Disabled"`
- **SQL Database** (`appdb`)
- **Virtual Network** + **Subnet** for the private endpoint
- **Private DNS Zone** + **VNet link** + **Private Endpoint** + **DNS Zone Group**

Names follow Azure CAF: `<abbr>-<workload>-<environment>-<instance>`.

## Configure

`subscriptionId` in `vars.pkl` reads from the `AZURE_SUBSCRIPTION_ID` env var, so nothing tenant-specific is checked in. Export it before running any command:

```bash
export AZURE_SUBSCRIPTION_ID=<your-sub-id>
```

Edit `vars.pkl` if you want to change `workload`, `environment`, `instance`, or `location`. Nothing else needs hand-curated IDs.

## Apply

```bash
formae eval main.pkl                                       # render & validate locally
formae apply --mode reconcile --yes --watch main.pkl       # deploy
```

Or apply without watching, then check status:

```bash
formae apply --mode reconcile --yes main.pkl
formae status command --query 'client:me' --output-layout detailed
```

## Validate the constraints

The stack uses Pkl type constraints. Try breaking them — every error is caught client-side, before the agent is contacted:

```bash
formae eval --location frankfurt main.pkl
# → Expected value of type `"westeurope"|"northeurope"|"francecentral"`, but got `"frankfurt"`

formae eval --instance abc main.pkl
# → Type constraint `matches(Regex(#"^\d{3}$"#))` violated. Value: "abc"

formae eval --db-sku Premium99 main.pkl
# → Expected value of type `"Basic"|"S0"|"S1"`, but got `"Premium99"`
```

Errors that Pkl accepts but Azure rejects (plugin or runtime validation) surface in `az monitor activity-log list -g <rg> --offset 5m`, not in `formae.log`.

## Tear down

```bash
formae destroy --query 'stack:stack-formae-demo-dev'
```

Cost while running: ~€4.40/month (SQL Basic) + ~€7/month (Private Endpoint) ≈ €12/month.

## Gotchas worth knowing

- **SQL Server's `administratorLogin` looks optional but is effectively required** unless you set the inline `administrators { ... azureADOnlyAuthentication = true }` block (the stack does this). Without it, Azure rejects the create with `Invalid value given for parameter Login` — and that error only surfaces in `az monitor activity-log`.
- **Destroy → re-apply with the same name works, but Azure does extra work.** Azure soft-deletes SQL logical servers for up to 5 days and reserves the name. Creating a server with the same name in the same subscription releases the soft-deleted record automatically — you don't wait the retention window and you don't need to restore. The new server provisions normally. If you'd rather sidestep the soft-deleted record entirely (and keep the option of restoring it via Azure support during the window), bump `instance` in `vars.pkl` (`001` → `002`).
