# Bug: Two Azure private networking resources silently "created" — private endpoint DNS broken

## Summary

Two resources in [`formae-bootstrap`](https://github.com/platform-engineering-labs/formae-bootstrap) are reported as successfully created by `formae apply` but never actually provisioned in Azure. Together they break private DNS resolution for the Postgres endpoint, so the formae agent container cannot connect to its database.

1. **`AZURE::Network::PrivateDnsZoneGroup`** — created empty (no `privateDnsZoneConfigs`), so no A record is written to the private zone. Root cause: PKL serialization bug.
2. **`AZURE::Network::PrivateDnsZoneVirtualNetworkLink`** — the ARM API call fails (transient/race condition after DNS zone LRO completes), engine swallows `OperationStatusFailure` and marks the resource created. Without the VNet link, DNS queries from within the VNet are not answered by the private zone.

Both bugs share the same engine-level symptom: `formae apply` reports `✓ + create <resource>` for resources that do not exist in Azure.

## Reproduction

[`formae-bootstrap`](https://github.com/platform-engineering-labs/formae-bootstrap) commit `1eeebab2e3f8336e09d14ec2a3a07efacafc0bd7`, `azure/bootstrap.pkl`, `--access public`, region `westeurope`.

```bash
formae apply --mode reconcile azure/bootstrap.pkl \
  --access public --location westeurope \
  --status-output-layout detailed --yes
```

Apply finishes with:

```
✓ + create formae-bootstrap-pdns-link       ← VNet link "created"
✓ + create formae-bootstrap-db-pe-dns       ← zone group "created"
```

## Expected

```bash
# VNet link exists
az network private-dns link vnet list \
  -g formae-bootstrap-rg -z privatelink.postgres.database.azure.com
# → one entry with provisioningState: Succeeded

# Zone group has configs
az network private-endpoint dns-zone-group show \
  -g formae-bootstrap-rg \
  --endpoint-name formae-bootstrap-db-pe \
  -n formae-bootstrap-db-pe-dns
# → privateDnsZoneConfigs: [...] with the zone ID

# A record written automatically
az network private-dns record-set list \
  -g formae-bootstrap-rg -z privatelink.postgres.database.azure.com
# → A record pointing to 10.100.1.5 (private endpoint IP)
```

## Actual

```bash
# No VNet links
az network private-dns link vnet list \
  -g formae-bootstrap-rg -z privatelink.postgres.database.azure.com
# → []

# Zone group empty
az network private-endpoint dns-zone-group show \
  -g formae-bootstrap-rg \
  --endpoint-name formae-bootstrap-db-pe \
  -n formae-bootstrap-db-pe-dns
# → {}

# Only SOA record, no A record
az network private-dns record-set list \
  -g formae-bootstrap-rg -z privatelink.postgres.database.azure.com
```

The agent container fails with:

```
ERR Failed to run migrations error="failed to connect to `user=formae database=formae`:
20.73.53.82:5432 (formae-bootstrap-db.postgres.database.azure.com): dial error: timeout:
dial tcp 20.73.53.82:5432: connect: connection timed out"
```

The FQDN resolves to the public IP (`20.73.53.82`) instead of the private endpoint IP (`10.100.1.5`).

## Workaround

Create both resources manually:

```bash
# 1. VNet link
VNET_ID=$(az network vnet show -g formae-bootstrap-rg -n formae-bootstrap-vnet --query id -o tsv)
az network private-dns link vnet create \
  -g formae-bootstrap-rg \
  -z privatelink.postgres.database.azure.com \
  -n formae-bootstrap-pdns-link \
  -v "$VNET_ID" -e false

# 2. A record (zone group configs are also broken; add the record directly)
PE_NIC=$(az network private-endpoint show \
  -g formae-bootstrap-rg -n formae-bootstrap-db-pe \
  --query "networkInterfaces[0].id" -o tsv)
PRIVATE_IP=$(az network nic show --ids "$PE_NIC" \
  --query "ipConfigurations[0].privateIPAddress" -o tsv)
az network private-dns record-set a add-record \
  -g formae-bootstrap-rg \
  -z privatelink.postgres.database.azure.com \
  -n formae-bootstrap-db \
  -a "$PRIVATE_IP"
```

## Root cause — Bug 1: PrivateDnsZoneGroup (PKL serialization)

`PrivateDnsZoneConfig` in `privatednszonegroup.pkl` (v0.1.8 and current `main`) is a plain `class`, not `extends formae.SubResource`:

```pkl
class PrivateDnsZoneConfig {
    name: String(length >= 1 && length <= 80)
    privateDnsZoneId: String|formae.Resolvable   // ← Resolvable never resolved
}
```

The formae engine does not resolve `Resolvable` values inside plain nested PKL classes (only `SubResource` descendants get resolved). In `bootstrap.pkl`, the field is set as `privateDnsZoneId = dnsZone.res.id` (a Resolvable). When serialized to JSON for the Go provisioner, `privateDnsZoneId` arrives as an object, not a string:

```go
zoneID, _ := cMap["privateDnsZoneId"].(string)  // type assertion fails → ""
if name == "" || zoneID == "" {
    return ..., fmt.Errorf("privateDnsZoneConfigs[%d] requires name and privateDnsZoneId", i)
}
```

`buildParams` returns an error → `Create()` returns `nil, err` → formae engine (v0.88.x/0.89.x) marks resource as created anyway → Azure creates the zone group with no configs → no A record.

**Related:** commit `112af9a7d5` (`fix(schema): migrate plain nested classes to formae.SubResource`) fixed 86 nested classes but missed `PrivateDnsZoneConfig` (and `PrivateLinkServiceConnection` in `privateendpoint.pkl`).

### Fix for Bug 1

```pkl
// privatednszonegroup.pkl
class PrivateDnsZoneConfig extends formae.SubResource {   // add extends
    name: String(length >= 1 && length <= 80)
    privateDnsZoneId: String|formae.Resolvable
}
```

## Root cause — Bug 2: PrivateDnsZoneVirtualNetworkLink (engine swallows OperationStatusFailure)

`PrivateDnsZoneVirtualNetworkLink` correctly extends `formae.Resource`; its `virtualNetworkId: String|formae.Resolvable` is resolved by the engine. The ARM API call itself fails — likely a transient/race condition where the DNS zone LRO has just completed but Azure's control plane hasn't propagated the zone state before the VNet link creation is attempted:

```go
poller, err := l.api.BeginCreateOrUpdate(ctx, rgName, zoneName, linkName, params, nil)
if err != nil {
    return &resource.CreateResult{
        ProgressResult: &resource.ProgressResult{
            OperationStatus: resource.OperationStatusFailure,
        },
    }, nil    // ← no Go error returned; result carries OperationStatusFailure
}
```

The formae engine receives `OperationStatusFailure` in the result but reports the resource as successfully created. The VNet link is never created in Azure. Without it, DNS queries from VMs within the VNet are not answered by the private zone, so the FQDN resolves to the public IP.

### Fix for Bug 2

Engine-level: `OperationStatusFailure` returned by a plugin's `Create()` must cause the formae agent to mark the resource as failed and surface an error, not report success. This is an engine fix, not a plugin fix.

As a plugin-side mitigation, the VNet link provisioner could implement a `Get()`-based verification step before returning, retrying the ARM call if the result is not yet visible. However, the correct fix is in the engine.

## Environment

- formae CLI: `0.89.0`
- azure plugin: `0.1.8`
- formae-bootstrap commit: `1eeebab2e3f8336e09d14ec2a3a07efacafc0bd7`
- Region: `westeurope`
