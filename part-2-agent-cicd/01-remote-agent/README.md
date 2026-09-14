# 01 · Install the formae agent on Azure

Stand up the remote agent exactly as the
[official formae docs](https://docs.formae.io/documentation/guides/install-agent-azure)
recommend, using the [`formae-bootstrap`](https://github.com/platform-engineering-labs/formae-bootstrap)
installer.

**Pin:** `0f3d336f2fcb6c67866caaec266940ab58921241` (2026-07-24, current `main`
as of 2026-08-12).

## What it deploys

- Resource group, VNet, subnet, NSG, public IP (egress) + VM running the agent
  container.
- PostgreSQL Flexible Server — the formae state store — private-endpoint only.
- The remote agent operates Azure with a **service principal** (SP creds ride
  the CustomScript's `protectedSettings`).

## Access modes

- `public` (default): self-signed HTTPS at `<name>.<location>.cloudapp.azure.com:49684`, `--allowed-cidr`.
- `appgw`: Application Gateway v2 + Key Vault cert, `--domain`.
- `tailnet`: private, Tailscale, trusted `*.ts.net` cert.

## How to install

1. Prereqs: local formae CLI + azure plugin + local agent; `az login`; a
   `Contributor` service principal; an SSH key.
2. Clone `formae-bootstrap` at the pinned commit,
   run `azure/scripts/gen-api-credential.sh`.
3. `formae apply --mode reconcile azure/bootstrap.pkl --access public
   --location <loc> --subscription-id <sub> --tenant-id <t> --client-id <sp-appid>
   --client-secret '<sp-pw>' --api-password-hash '<hash>' --db-password '<dbpw>'
   --ssh-public-key "$(cat ~/.ssh/id_ed25519.pub)" --watch`.
4. Connect: `curl -k https://formae-bootstrap.<loc>.cloudapp.azure.com:49684/api/v1/health`,
   then `azure/scripts/write-bootstrap-profile.sh --profile bootstrap --access
   public --fqdn formae-bootstrap.<loc>.cloudapp.azure.com --user formae
   --password '<pw>'`, then `formae agent status --profile bootstrap`.

Follow the [official guide](https://docs.formae.io/documentation/guides/install-agent-azure)
for `appgw`/`tailnet` extras and flag details.

## Upgrade & teardown

Re-apply the same `bootstrap.pkl` with a newer
`--formae-image ghcr.io/platform-engineering-labs/formae:<ver>` (same flags,
same `--db-password`), then `formae update <ver>`. **Keep the local install you
bootstrapped from** — it holds the agent's own infra in state. Tear down:
`formae destroy --query "stack:formae-bootstrap-azure"` then
`formae apply --mode destroy azure/destroy-target.pkl`.