# 01 · Install the formae agent on Azure

Stand up the remote agent exactly as the
[official formae docs](https://docs.formae.io/documentation/guides/install-agent-azure)
recommend, using the [`formae-bootstrap`](https://github.com/platform-engineering-labs/formae-bootstrap)
installer.

**Pin:** `7397adce` (PR [#10](https://github.com/platform-engineering-labs/formae-bootstrap/pull/10),
not yet merged as of 2026-09-15). Agent runs formae `0.89.0` — matches local CLI.

> **Access mode used in this series:** `tailnet` (Tailscale). The `public` mode
> has a known TLS regression in 0.89.0 that PR #10 fixes but the fix requires
> you to supply your own cert. Tailscale issues a trusted `*.ts.net` cert
> automatically and avoids the problem entirely. See
> [formae-findings-2026-09-14.md](../formae-findings-2026-09-14.md) for details.

## What it deploys

- Resource group, VNet, subnet, NSG + VM running the agent container.
- PostgreSQL Flexible Server — the formae state store — private-endpoint only.
- The remote agent operates Azure with a **service principal** (SP creds ride
  the CustomScript's `protectedSettings`).

## Access modes

- `public`: HTTPS at `<name>.<location>.cloudapp.azure.com:49684` — requires
  `--cert-file`, `--key-file`, `--domain` (operator-supplied cert, PR #10+).
- `appgw`: Application Gateway v2 + Key Vault cert, `--domain`.
- `tailnet`: private, Tailscale, trusted `*.ts.net` cert — **used in this series**.

## How to install (tailnet)

1. Prereqs: local formae CLI + azure plugin + local agent; `az login`; a
   `Contributor` service principal; an SSH key; a Tailscale account with
   **HTTPS certificates enabled** (Admin → DNS → Enable HTTPS) and a reusable
   auth key tagged `tag:formae`.
2. Clone `formae-bootstrap`, checkout PR #10 branch (`naxty/fixCC`),
   run `azure/scripts/gen-api-credential.sh` — note the plain-text password.
3. Deploy:
   ```bash
   formae apply --mode reconcile azure/bootstrap.pkl \
     --access tailnet \
     --ts-authkey tskey-auth-xxxxx \
     --ts-hostname formae-bootstrap \
     --location westeurope \
     --subscription-id <sub> --tenant-id <t> --client-id <sp-appid> \
     --client-secret '<sp-pw>' \
     --api-password-hash '<hash>' --db-password '<dbpw>' \
     --ssh-public-key "$(cat ~/.ssh/id_ed25519.pub)" \
     --status-output-layout detailed --yes
   ```
4. Generate profile and verify:
   ```bash
   azure/scripts/write-bootstrap-profile.sh \
     --profile bootstrap --access tailnet \
     --fqdn formae-bootstrap.<tailnet-name>.ts.net \
     --user formae --password '<plain-text-pw>'

   formae agent status --profile bootstrap
   ```
   Plugins on the deployed agent: AWS 0.1.16 · AZURE 0.1.10 · GCP 0.1.12 · K8S 0.1.10.

Follow the [official guide](https://docs.formae.io/documentation/guides/install-agent-azure)
for `appgw` details and full flag reference.

## Upgrade & teardown

Re-apply the same `bootstrap.pkl` with a newer
`--formae-image ghcr.io/platform-engineering-labs/formae:<ver>` (same flags,
same `--db-password`), then `formae update <ver>`. **Keep the local install you
bootstrapped from** — it holds the agent's own infra in state. Tear down:
`formae destroy --query "stack:formae-bootstrap-azure"` then
`formae apply --mode destroy azure/destroy-target.pkl`.