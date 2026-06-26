Step 1 — The problem: state files are the leaky abstraction

Terraform sold us a great idea: declare what you want, let the tool figure out how to get there. It mostly delivers on that — until you remember the second character in the play. The state file.

Every Terraform user has a relationship with state. It starts polite. The file sits in a backend somewhere, you run apply, things happen. Then the relationship gets complicated.

You write code that says what should exist. State decides what does exist. When those two disagree, you have a problem with no clean fix.

Take the most ordinary scenario: a resource already exists in the cloud. Maybe the network team built the VNet last quarter. Maybe a colleague hit "Deploy" in the portal during an incident. Maybe a prior version of the code created it and you've since lost the state. The resource is there. You want Terraform to manage it. So you do what the docs say:

- Add an import block. But only in the root module — child modules can't declare imports. So if your VNet belongs in modules/network/, you can't put the import next to the resource. It has to live up top, far from the code it concerns, and someone reading the module six months from now will have no idea it exists.
- Or use terraform import on the CLI. But only if the provider supports it for that resource — and a non-trivial number of resources still don't, especially in the newer or community providers. When it isn't supported, your options reduce to "edit the state file by hand" or "destroy and recreate," and neither is a real answer in production.

Even when import works, it imports one resource at a time. A VNet with three subnets, four NSG rules, and a peering is a thirty-minute job of incantations and matching ARM IDs by eye.

Now layer in the rest:

- State locks. The backend grabs a lock when an apply starts. Pipeline crashes mid-apply, leaves the lock dangling, and now nobody on the team can run anything against that environment until somebody with the right permissions finds the lock ID and runs force-unlock. The lock isn't protecting anything anymore — it's just blocking you.
- Drift. Someone clicks something in the portal. Could be a security patch, could be a typo, could be a feature flag flipped to test something at 2am. Your next plan either tries to revert it (good luck explaining that to the team that made the change) or you spend the morning writing ignore_changes blocks to pretend the drift doesn't exist.
- State file as bottleneck. It's a single mutable file. Two people can't safely work on the same stack at the same time. Splitting state across stacks helps but introduces its own pain: cross-stack references via terraform_remote_state are brittle, and a destroy in one stack can silently break another.

Here's the throughline: Terraform's state file makes the tool's view of the world the source of truth, and the actual cloud the thing that has to be wrestled into agreement. That gets the relationship backwards. The cloud is what's real. The tool should be observing it, not asserting against it.

That backwards relationship is what generates almost every operational pain Terraform users know by heart — the locks, the imports, the drift, the ignore_changes graveyard. None of those are bugs. They're the cost of running a state machine that can't see the system it's supposed to control.

In the next section, I'll show what happens when you start with the opposite assumption.

---
A few choices baked in I'd like your read on:

- Tone. Frustrated-but-fair, not Terraform-bashing. Terraform is the genre standard; the post earns the right to critique by acknowledging what it got right first.
- Length. ~450 words. Long enough to make the specific points land, short enough to keep momentum.
- What I dropped from your bullet: I left out the literal .tfstate file extension — felt too low-level for the opening. Easy to add back if you want.
- The throughline argument ("cloud is real, tool should observe it") is doing the heavy lifting to set up Step 2. If you want a softer landing into Formae, I can pull that out and let Step 2 do its own setup.


_______________________________________


Step 2 — The discovery: what if the cloud is the source of truth?

The opposite assumption looks like this: the cloud already knows what exists. The tool's job is to observe it, then converge it toward what you declared. No file in a bucket. No lock to fight over. The "state" is just the running infrastructure, scanned continuously by something that lives close to it.

That something is the Formae agent. It sits in your environment (your laptop, a container, a VM), holds credentials to one or more cloud subscriptions, and does two things on a loop:

1. Discovers what's actually in those subscriptions — every resource, every property, even the ones you never wrote code for.
2. Reconciles that picture against the forma files you point it at, creating, updating, or deleting resources so reality matches intent.

That's the whole mental model. There is no .tfstate in this picture. There is no terraform_remote_state. There is no force-unlock. The agent's view of the cloud and your declarative code are the only two things in the system, and the agent is responsible for making them agree.

The second bet is the language. Formae uses Pkl — Apple's configuration language. HCL is a configuration format that grew a validation block and a few functions; you can stop a bad region from getting through terraform plan, but the constraint lives on the input variable and stops being enforced the moment the value flows into a module. Pkl is a typed language that happens to be used for configuration. A constraint is a type, and that type travels with the value through every assignment, function call, and resource attribute. Validation isn't a feature bolted onto inputs — it's how the language works.

The next section will show what that feels like in practice; for now the contrast in primitives is what matters.

Now look at what each bet undoes from Step 1:

- No state file → no lock, no drift war, no rebase fights over a JSON document. The agent reads reality; reality doesn't conflict-merge.
- Discovery → no import block ceremony. If the resource exists in a subscription the agent can see, Formae already knows about it. You decide whether to leave it alone (unmanaged) or adopt it into a stack — but you don't have to tell Formae it exists.
- Typed language → most validation errors die on your laptop. Wrong region, malformed name, unsupported SKU — caught before the cloud ever sees the request, and caught even when the value is three function calls deep.

This isn't magic, and the next two sections will show where the seams are. But the shift in primitives — agent over state file, Pkl over HCL — is the thing worth understanding first. Everything else about Formae is downstream of those two choices.

---
~440 words. Changes from the previous draft:

- Snippet pair removed.
- Language paragraph now makes the honest claim ("validation that travels with the type, vs. validation on input variables") in prose, with one beat of acknowledgement that HCL has something there.
- Last bullet rephrased to reinforce that point ("caught even when the value is three function calls deep") rather than re-asserting "client-side validation" generically.


______________________________________________


Step 3 — The greenfield experience: writing a stack from scratch

To get a real read on Formae, I built a small but realistic Azure stack from a blank file. Nine resources: a resource group, a User-Assigned Managed Identity acting as the SQL server's only admin, the SQL server itself with no public network path, a database, a virtual network, a subnet, a private DNS zone, a VNet link, a private endpoint, and a DNS zone group to wire it all together. About 200 lines of Pkl, end to end.

Three things stood out while writing it.

References are values, not strings

In Terraform, aws_subnet.app.vpc_id = aws_vpc.main.id is a string interpolation that Terraform inspects to build the dependency graph. The graph is implicit; you trust it works.

In Pkl, the reference is the value:

pkl
local rg = new resourcegroup.ResourceGroup {
label = "rg-\(suffix)"
name = label
location = stackLocation
}

local mi = new userassignedidentity.UserAssignedIdentity {
label = "id-\(suffix)"
name = label
location = rg.location              // computed locally
resourceGroupName = rg.res.name     // resolved at apply by the agent
}

Two flavours of reference, and the distinction matters. rg.location is a Pkl value — the literal string I assigned five lines earlier, available immediately at eval time. rg.res.name is a resolvable: the agent fills it in at apply time from the live resource. The type system enforces that you can't accidentally treat one like the other. The dependency graph is just what the references happen to imply — there is no depends_on block in the entire file.

By the time I'd wired the SQL server to the MI to the resource group, and the private endpoint to the subnet to the VNet, the whole graph existed without me ever drawing it.

Constraints fire on your laptop

This is where Pkl earns its keep over HCL. Three properties in the file have typed constraints:

pkl
typealias AllowedLocation = "westeurope" | "northeurope" | "francecentral"
typealias AllowedDbSku = "Basic" | "S0" | "S1"

local stackLocation: AllowedLocation = properties.location.value
local stackInstance: String(matches(Regex(#"^\d{3}$"#))) = properties.instance.value
local dbSkuName: AllowedDbSku = properties.dbSku.value

Pass --location frankfurt and the error arrives instantly, with a stack trace pointing at the use site:

Expected value of type `"westeurope"|"northeurope"|"francecentral"`, but got `"frankfurt"`

No network call. No agent involvement. No Azure 400 ten minutes into an apply. The constraint is part of the type, so it fires at the moment Pkl renders the file — which is the moment I save it in my editor and run formae eval.

The interesting wrinkle: Pkl catches type violations, but it can't catch values that look right and are wrong. A SKU named Standard_DS99_v999 would pass an unrestricted String field, sail through the agent, and get rejected by Azure with an activity-log entry you have to go hunt for. Formae has three validation layers — Pkl, plugin, Azure runtime — and only the first is free. The other two cost you a round trip.

eval is the inner loop

In Terraform, the feedback loop is init → plan → read wall of output. In Formae it's eval and the agent isn't even involved. The command renders the entire forma as JSON, runs every constraint, resolves every Pkl value, and either prints the result or fails with a precise error.

formae eval main.pkl                   # full render
formae eval --instance 042 main.pkl    # try a property override

Both return in well under a second. The whole "what would this apply produce" question gets answered without touching the cloud. By the time I ran my first real apply, I'd run eval maybe twenty times.

And then the apply

formae apply --mode reconcile --yes --watch --status-output-layout detailed main.pkl

The first surprise: the apply is asynchronous. The CLI hands the forma to the agent, which queues it, breaks it into per-resource operations, and starts executing. The --watch flag keeps the terminal in sync; without it, the command would return immediately and you'd check status from another shell. This is a real shift from terraform apply's "I am the apply, my exit is the apply's exit." You're submitting work to a daemon.

The Azure SQL server took a few minutes (it always does), and because nine resources are wired into a dependency graph, the agent created the network and identity layer in parallel while the SQL server provisioned, then bolted the private endpoint and database on top. The output stream showed each resource's state transitioning live — Pending → InProgress → Success — with no Still creating... polling theatre. It's the agent's job to know what's happening; my job was to wait.

That's the part you don't notice until later: I never opened the Azure portal during this. Not to find an ARM ID, not to import an existing resource, not to verify a result. The stack went from blank file to running infrastructure entirely through eval and apply.

---
~640 words — slightly longer than Steps 1-2 because it's the demo section and earns the extra length.

Choices baked in:

- Three callouts, not five. References, constraints, eval loop. The apply section sits at the end as a fourth beat but is shorter and serves as the segue.
- Snippets are real, lifted from main.pkl. Nothing invented for the post.
- What I deliberately didn't show. The full forma { ... } block (too long for a post), the Private Endpoint wiring (visually noisy, doesn't add to the argument), the properties { ... } declarations (mentioned in passing).
- Async apply as a callout. This is genuinely different from TF and worth naming. It also sets up the "honest critique" section in Step 5 (the agent model has real implications — single point of failure, harder to debug, etc.).