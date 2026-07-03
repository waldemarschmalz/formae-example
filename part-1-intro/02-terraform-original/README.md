# Part 1 · Terraform original — Azure SQL behind a Private Endpoint

The **starting point** for the migration story. Same eleven Azure resources as [`../01-from-scratch/`](../01-from-scratch/), written in Terraform + `hashicorp/azurerm ~> 4.0`. Deploy this first — [`../03-terraform-migrated/`](../03-terraform-migrated/) picks it up and puts Formae in front of it (synchronisation, discovery, drift/click-ops handling).

## What gets deployed

- **Resource Group** (`rg-tf-demo-dev-001`)
- **User-Assigned MI** as the SQL server's Entra-only admin
- **Role Assignment**: MI → Reader on the resource group
- **Azure SQL Server**: system-assigned identity, AAD-only auth, public network access disabled
- **SQL Database** (`appdb`, Basic SKU by default)
- **VNet** (`10.10.0.0/16`) + **Subnet** (`10.10.1.0/24`)
- **Private DNS Zone** (`privatelink.database.windows.net`) + VNet link
- **Private Endpoint** for the SQL server + DNS zone group

Default workload name is `tf-demo`, so this stack can coexist in one subscription with the `formae-demo` stack in `01-from-scratch/`.

## Constraints

Three input variables use `validation {}` blocks — they fail at `terraform plan`, before any Azure call:

| Variable | Constraint |
|---|---|
| `instance` | regex `^\d{3}$` |
| `location` | `westeurope \| northeurope \| francecentral` |
| `db_sku_name` | `Basic \| S0 \| S1` |

## Prerequisites

```bash
az login
az account set --subscription <id>
```

The provider uses `az` credentials by default.

## Deploy

`subscription_id` has no default — pass it on every `terraform` command (or export `TF_VAR_subscription_id`):

```bash
export TF_VAR_subscription_id=<your-sub-id>
terraform init
terraform plan
terraform apply
```

Or override any variable inline:

```bash
terraform apply -var=location=northeurope -var=db_sku_name=S0
```

## Constraint demo

```bash
terraform plan -var=location=frankfurt
# → Error: Invalid value for variable: location must be one of: westeurope, northeurope, francecentral.

terraform plan -var=instance=abc
# → Error: Invalid value for variable: instance must be exactly three digits, e.g. "001".

terraform plan -var=db_sku_name=Premium99
# → Error: Invalid value for variable: db_sku_name must be one of: Basic, S0, S1.
```

## Tear down

```bash
terraform destroy
```

Cost while running: ~€4.40/month (SQL Basic) + ~€7/month (Private Endpoint) ≈ €12/month.

## Notes

- **State is local** (`terraform.tfstate` in this directory) — fine for a demo. For real use, switch to an Azure Storage backend.
- **Structural differences worth flagging before the migration:**
  - `azurerm_mssql_server` exposes `azuread_administrator` as a nested block; the Pkl plugin models the same thing as an inline `administrators` object on `Server`.
  - `azurerm_private_endpoint` rolls the DNS zone group into the endpoint resource; the Pkl plugin splits them into `PrivateEndpoint` + `PrivateDnsZoneGroup`.

## What's next

Once this stack is deployed, head to [`../03-terraform-migrated/`](../03-terraform-migrated/) — that's where Formae discovers these resources, adopts them into a stack, and shows what happens when you edit them from the portal or from Terraform behind Formae's back.
