# Ideas / parking lot

Things that came up while drafting but don't belong in the post being written right now.

---

## Splitting a stack across teams / lifecycles

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
