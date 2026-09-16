# 03 · Observability

Managed Grafana + Azure Monitor Workspace — the layer that makes drift visible
before it becomes an incident.

## What it deploys

- **Azure Monitor Workspace** — receives OpenTelemetry metrics from the formae agent
- **Azure Managed Grafana** — pre-built formae dashboards, linked to the workspace
- **OTel Collector** — sidecar in the agent container, ships formae metrics to Azure Monitor

## Payoff

1. Stack deployed. Grafana live.
2. Out-of-band change in Azure Portal.
3. Drift counter ticks in Grafana.
4. Next CI run (`formae eval`) surfaces the drift in the PR check.
5. Merge → `formae apply --mode reconcile` corrects it.
6. Grafana shows drift resolved.

## Deploy

```bash
formae apply --mode reconcile 03-observability/main.pkl \
  --location westeurope \
  --grafana-admin-email you@example.com
```

> **Cost:** Managed Grafana Essential ~€8/mo + Azure Monitor Workspace ingestion ~€0.25/GiB.
> Tear down with `formae destroy --query 'stack:formae-observability'` when done.

## Contents

- `main.pkl` — formae stack: Azure Monitor Workspace + Managed Grafana
- (planned) OTel Collector config — wired as sidecar in agent container
