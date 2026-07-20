# Formae by Example

Companion code for a blog series on [Formae](https://docs.formae.io/). Each part is a self-contained folder you can read top to bottom, eval, and apply.

- `part-1-intro/` — Formae basics and a Terraform-to-Formae migration of an Azure stack.
- `part-2-agent-cicd/` — Adds a remote Formae agent, CI/CD, and Key Vault secrets. (planned)
- `part-3-mcp/` — Driving Formae through an MCP server. (planned)

---

## What is a `main.pkl`?

A Formae stack is a single Pkl file (by convention `main.pkl`) that describes the desired infrastructure. There are four things to know:

1. **Stack** — a logical group that owns the resources. Every `forma` needs one.
2. **Target** — where the stack deploys (e.g. an Azure subscription). Replaces the provider blocks you know from Terraform.
3. **Properties** — typed inputs exposed as CLI flags (`--location`, `--instance`, ...). Defaults live in the file.
4. **`.res` references** — how one resource reads another's live values (`rg.res.name`, `mi.res.principalId`). Dependency order is inferred from these.

A minimal stack looks like this:

```pkl
amends "@formae/forma.pkl"
import "@formae/formae.pkl"
import "@azure/azure.pkl"
import "@azure/resources/resourcegroup.pkl"

forma {
    new formae.Stack { label = "my-stack" }

    new formae.Target {
        label = "azure-westeurope"
        config = new azure.Config { subscriptionId = "..." }
    }

    new resourcegroup.ResourceGroup {
        label = "rg-demo"
        name = label
        location = "westeurope"
    }
}
```

---

## The three commands you need

```bash
formae eval main.pkl                        # render the stack as JSON, validate locally
formae apply --mode reconcile --yes main.pkl
formae destroy --query 'stack:my-stack'
```

`eval` runs entirely on your machine — no agent, no cloud calls. Use it after every change.

`apply --mode reconcile` brings the live state in line with the file: creates what is missing, updates what drifted, deletes what was removed from the file. There is also `--mode patch` for additive changes that never delete.

Add `--watch` to stream progress, or check after the fact with:

```bash
formae status command --query 'client:me' --output-layout detailed
```

---

## Prerequisites

- Azure CLI logged in and the right subscription selected (`az login`, `az account set --subscription <id>`).
- A running Formae agent with the plugin you import:

```bash
sudo formae plugin install azure@0.1.6
sudo formae agent stop && formae agent start
```

The plugin version in the agent must match the version in `PklProject` — otherwise `apply` silently skips the namespace.

---

## Best practices

- **`eval` before `apply`.** It's free and catches schema errors, missing properties, and bad references before the agent is contacted.
- **One `Stack` per file.** Keep stacks small and focused; reference outputs across stacks only when you have a real reason to.
- **Name with a convention.** This series uses Azure CAF: `<abbr>-<workload>-<environment>-<instance>`. Pick something and stay consistent — names show up in every error message.
- **`local` only when needed.** Mark a resource `local` when other resources reference it; otherwise let it stand alone.
- **Use `.res` for cross-references, never string concatenation.** `rg.res.name` is type-checked and orders dependencies for you.
- **Constrain `Property` types.** Pkl typealiases and regex constraints catch typos client-side (see `part-1-intro/01-from-scratch/` for a worked example).
- **Pin plugin versions** in `PklProject` and install the exact same version on the agent.
- **Read the activity log when `apply` fails silently.** Some plugin/Azure rejections never reach `formae.log`; `az monitor activity-log list -g <rg> --offset 5m` is where they land.

---

## Where to go next

Start with [`part-1-intro/01-from-scratch/`](./part-1-intro/01-from-scratch/) — an Azure stack that demonstrates every concept above end to end.
