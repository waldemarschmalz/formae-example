## TF data?

Where did data go?

If you've spent time with Terraform, your fingers know the shape: you need the ID of a VNet your platform team owns, so you write

hcl
data "azurerm_virtual_network" "lz" {
name                = "vnet-lz-prod-001"
resource_group_name = "rg-lz-prod"
}

resource "azurerm_subnet" "app" {
virtual_network_name = data.azurerm_virtual_network.lz.name
# ...
}

The data block is a read-only lookup. It runs at plan time, fetches the live values, and lets you wire them into resources you own. Without it, the two worlds — what you manage and what someone else manages — can't talk.

Formae has no data block, and once you see why, you stop missing it.

A Formae Target continuously discovers what's already in the cloud. That platform-team VNet shows up in Formae's view of the world as an unmanaged resource — Formae knows it exists, won't touch it on apply, won't try to update it, won't delete it on reconcile. But because Formae knows about it, you can reference its properties from your own resources the same way you'd reference one of your own:

pkl
new subnet.Subnet {
label = "snet-app-prod-001"
name = label
virtualNetworkName = lzVnet.res.name   // unmanaged, but referenceable
addressPrefix = "10.20.1.0/24"
}

You manage the subnet. The platform team manages the VNet. Both live in the same dependency graph, and if they re-deploy the VNet, your subnet doesn't care — the reference resolves against whatever the live resource looks like, not against an ID you pasted in six months ago.

The mental shift is this: in Terraform, every cross-boundary read is an explicit data declaration. In Formae, the boundary is just management ownership — and references don't care which side of the line a resource sits on. You declare a data block in Terraform to make the read possible; in Formae, the read is already possible, and what you're really deciding is who owns the lifecycle.

There's one prerequisite worth being honest about: the resource has to be visible to a Formae Target your agent can reach. If the VNet sits in a subscription Formae can't see, Discovery never picks it up, and you fall back to passing the ID in as a Property — a plain string, no dependency graph, the same fragility Terraform has when you skip data and hardcode an ID. That fallback exists, but it's not where you want to live.

---
A couple of choices to make:

- Code example fidelity. I made up lzVnet as a stand-in. If you want, I can wire a real one against the Azure plugin's discovered-resource syntax — I'd want to double-check the exact accessor shape against the docs first, since I haven't seen it in your 01-from-scratch/ yet.
- Length. This is ~350 words. If you want a tighter version for a "compared to Terraform" callout box, say so and I'll cut it in half.