# formae findings — 2026-09-14

Reproduction env: `formae-bootstrap` commit `1eeebab2e3f8336e09d14ec2a3a07efacafc0bd7`, `--access public`, region `westeurope`, formae CLI `0.89.0`, azure plugin `0.1.8`.

---

## Bug 1 — `PrivateDnsZoneGroup` silently created empty

> Full GitHub issue (ready to post): [github-issue-privatednszonegroup.md](github-issue-privatednszonegroup.md)

**Symptom:** `formae apply` reports `✓ + create formae-bootstrap-db-pe-dns` but the zone group has no `privateDnsZoneConfigs` in Azure. No A record is written → private DNS broken → agent container connects to public IP instead of private endpoint.

**Root cause:** `PrivateDnsZoneConfig` in `privatednszonegroup.pkl` is a plain `class`, not `extends formae.SubResource`. The engine only resolves `Resolvable` values inside `SubResource` descendants. `privateDnsZoneId` is declared as `String|formae.Resolvable` and set to `dnsZone.res.id` (a Resolvable) in `bootstrap.pkl`. Because the class is plain, the field arrives unresolved in the Go provisioner, the string assertion fails (`""`), `buildParams` returns an error, and the engine (v0.88+/0.89) swallows the error and marks the resource created.

Related: commit `112af9a7d5` (`fix(schema): migrate plain nested classes to formae.SubResource`) fixed 86 similar classes but missed `PrivateDnsZoneConfig` (and likely `PrivateLinkServiceConnection` in `privateendpoint.pkl`).

**Fix applied locally** to `/opt/pel/formae/plugins/azure/v0.1.8/schema/pkl/network/privatednszonegroup.pkl`:

```diff
-class PrivateDnsZoneConfig {
+/// One configuration entry binding a private DNS zone to the private endpoint's
+/// auto-generated A record.
+@azure.SubResourceHint { apiVersion = module.apiVersion }
+class PrivateDnsZoneConfig extends formae.SubResource {
```

Note: PKL requires doc comment **before** annotation — annotation before doc comment causes `Dangling documentation comment` PKL error, which crashes the plugin at startup (the Extractor evaluates schema classes).

**Verified:** after fix + re-apply, zone group shows `privateDnsZoneConfigs` with correct zone ID and A record `10.100.1.5` provisioned automatically.

---

## Bug 2 — Engine swallows `OperationStatusFailure`

**Symptom:** `formae apply` reports `✓ + create formae-bootstrap-pdns-link` but the VNet link is not created in Azure.

**Root cause:** The `PrivateDnsZoneVirtualNetworkLink` ARM call fails (transient race — DNS zone LRO completes but Azure control plane hasn't propagated state before the link creation is attempted). The plugin's `Create()` returns `OperationStatusFailure` in the result struct (not a Go error). The engine receives `OperationStatusFailure` but reports the resource as successfully created.

This is an engine-level bug: `OperationStatusFailure` from a plugin's `Create()` must cause the resource to be marked failed and surfaced to the user, not silently marked created.

**No code fix applied** — engine fix needed. The link created successfully on re-apply (transient condition resolved).

---

## CLI regression — `write-bootstrap-profile.sh` produces unloadable profile

**Symptom:**
```
Cannot find property `insecureSkipVerify` in object of type `formae.Config#ApiConfig`
```

**Root cause:** `write-bootstrap-profile.sh` generates a profile with `cli.api { insecureSkipVerify = true }`. The property `insecureSkipVerify` was removed from `ApiConfig` in a recent release. The new `Classic` connection type (`cli.connection = new Classic { url; port }`) has no TLS skip property either.

The bootstrap agent uses a self-signed CN-only cert (no SANs). Go 1.17+ rejects CN-only certs as "not standards compliant" regardless of system trust store. Without `insecureSkipVerify` (or equivalent), the formae CLI cannot connect to the bootstrap agent over HTTPS.

**Needs fix in one of:**
- Add `insecureSkipVerify` (or `tlsInsecure`) to `Classic` connection type
- OR bootstrap generates certs with proper SANs (e.g. via ACME / Let's Encrypt on the public FQDN)
- AND update `write-bootstrap-profile.sh` to emit the new format

### Workaround attempt — Let's Encrypt cert swap

Obtained a valid SAN cert via `certbot certonly --standalone` on the bootstrap VM (port 80 opened temporarily via NSG). Copied `fullchain.pem` / `privkey.pem` to `/var/formae/tls.crt` and `/var/formae/tls.key` (owned `1001:1001`).

**Result: agent container entered crash-loop.**

The agent runs as PID 1 inside the Docker container (`ghcr.io/platform-engineering-labs/formae:0.89.0`, `--restart always`). To hot-swap the cert we had to kill that process. Docker restarted the container but the agent refused to start with `agent is already running (PID 1)`. No PID file and no socket file found — state stored in Postgres. The agent likely persists a boot/lock record in the DB that it never cleaned up after the abrupt kill.

**Implication:** TLS cert cannot be swapped without a clean agent shutdown (graceful stop via the formae API or proper `docker stop`), and the bootstrap currently has no documented path to gracefully rotate TLS certs at runtime.
