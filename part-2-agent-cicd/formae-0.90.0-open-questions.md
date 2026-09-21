# formae 0.90.0 — Findings & Working Solution

Context: formae remote agent (Azure VM, Tailscale) + GitHub Actions CI/CD.
CLI 0.90.0, agent 0.90.0. Agent capabilities include `shared-drift-resolution`.

**Status: portal drift → CI reconciles → SOLVED via direct REST.**

---

## Working solution — portal drift reconcile from CI (verified end-to-end)

**Key insight:** the CLI's `--resolution` flag is broken for Classic profiles
(returns `Error: unsupported operation` before touching the server). Bypass the
CLI entirely; the agent's REST API works correctly.

**Verified sequence (this session):**

```
Azure state before:  managed-by=portal (drifted from declared)
Formae state store:  managed-by=portal (synchronizer absorbed)
Declared PKL:        managed-by=formae

1. POST /api/v1/admin/synchronize                     → force sync scan
2. POST /api/v1/commands (simulate=true, no resolution)
   → ReconcileRejected + ObservationID + ResourceID
3. POST /api/v1/commands (simulate=true, resolution=inline JSON with decisions)
   → 200 OK + ReviewID
4. POST /api/v1/commands (simulate=false, resolution includes ReviewID + IdempotencyKey)
   → 202 Accepted + CommandId
5. GET /api/v1/commands/{id}/status                   → poll until Success

Azure state after:   managed-by=formae (reverted to declared) ✅
```

**Resolution JSON schema:**
```json
{
  "ObservationID": "<from step 2>",
  "ReviewID": "<from step 3 — required only for real apply>",
  "IdempotencyKey": "<stable string — required only for real apply>",
  "Decisions": [
    {"ResourceID": "<from step 2>", "Action": "revert" | "absorb"}
  ]
}
```

**Verified curl (phase 3 — simulate with decisions):**
```bash
curl -u "$AUTH" -X POST "$BASE/api/v1/commands" \
  -H "Client-ID: my-ci-$(date +%s)" \
  -F "command=apply" \
  -F "mode=reconcile" \
  -F "simulate=true" \
  -F "resolution=$RESOLUTION_INLINE_JSON" \
  -F "file=@/tmp/forma.json;type=application/json"
```

**Critical detail:** `resolution` must be **inline JSON in the form field** (not
`resolution=@/path/to/file`). File-upload form of the resolution field parses
but decisions are ignored (still returns `ReconcileRejected`).

The forma file also uploads as `file=@evaluated.json` — run
`formae eval --output-schema json main.pkl > forma.json` first to pre-eval the
PKL (server can't process raw PKL with env-var references).

---

## Major discoveries (this session, in order)

### 1. Agent + CLI both 0.90.0
README pin doc is stale (says 0.89.0). Version mismatch ruled out as cause.

### 2. `--resolution` schema — extracted from binary strings
From `strings /opt/pel/bin/formae`:
> "JSON drift-resolution controls for soft reconcile: ObservationID, Decisions
> [{ResourceID, Action (absorb or revert)}], ReviewID, IdempotencyKey.
> Simulate the final choices first; real submission requires its ReviewID and a
> stable IdempotencyKey. Mutually exclusive with force.
> Requires shared-drift-resolution capability."

Corrections from prior session:
- **`ResourceID`** (Ksuid), not `ResourceLabel`
- **`Action`**, not `Decision`
- Values **`absorb` / `revert`**, not `AcceptChanges` / `RejectChanges`
- **Mutually exclusive with `--force`**

### 3. CLI `--resolution` broken for Classic profiles
CLI returns `Error: unsupported operation` before hitting the server, regardless
of file path (real, missing, malformed — all same error). Tested with all
combinations of `--mode`, `--simulate`, output flags. Likely wired only for
Hosted profile; Classic profile path is stubbed.

### 4. Direct REST API works with `shared-drift-resolution` capability
Agent has `Capabilities: ["command-metadata", "shared-drift-resolution", "desired-stack-extraction"]`.
`POST /api/v1/commands` with inline JSON in `resolution` form field works.

### 5. Simulate reads state store, NOT live Azure
Confirmed: after `az tag update`, simulate returned `ChangesRequired: false`
until synchronizer scanned. Synchronizer interval unknown (default appears
several minutes; `POST /admin/synchronize` triggers it manually).

### 6. `--force` is not a bypass — it's the re-apply after decision
Interactive TUI is `e` (extract) or `r` (revert), formae then re-applies
with `--force` internally. `--force` alone → agent rejects
(`State: Rejected`) because no decision was registered.

### 7. `POST /stacks/{stack}/reconcile` — one-shot revert endpoint
Requires `AutoReconcilePolicy` on the stack (403 without). Reverts ALL drift on
stack to last-known desired state. Useful for scheduled/manual reconcile;
requires stack-level policy declaration.

### 8. REST endpoints (from swagger)
```
POST /api/v1/admin/synchronize        # trigger synchronizer scan
POST /api/v1/admin/discover           # trigger discovery
POST /api/v1/admin/reap               # trigger reap
POST /api/v1/admin/check-ttl          # check TTL
POST /api/v1/commands                 # submit apply/destroy (multipart form)
GET  /api/v1/commands/{id}/status     # poll status
GET  /api/v1/commands/{id}/desired-delta
POST /api/v1/commands/cancel          # cancel in-progress
POST /api/v1/stacks/{stack}/reconcile # one-shot revert (needs auto-reconcile policy)
GET  /api/v1/stacks/{stack}/drift     # get current drift
GET  /api/v1/stacks/{stack}/changes-since-last-reconcile
GET  /api/v1/stacks | /resources | /policies | /targets | /generators | /health
```

---

## Design pattern for CI/CD (updated)

**PR (eval):**
```
1. formae eval main.pkl                       # local PKL validation
2. formae apply --simulate --force ...        # server-side drift preview
3. If ChangesRequired=true: post PR comment showing diff
4. If ReconcileRejected: post PR comment "Out-of-band drift; merge to reconcile"
```

**main (apply):**
```
1. formae eval --output-schema json main.pkl > forma.json
2. curl POST /commands (simulate=true, no resolution)
   → capture Observation (if any) and CommandId
3a. If no observation, ChangesRequired=false: exit 0
3b. If no observation, ChangesRequired=true: normal apply (formae CLI or curl)
3c. If ReconcileRejected: build resolution JSON with Action=revert for every
    ModifiedResource, POST simulate + POST real, poll to Success
```

For 3c, use REST (not CLI) until CLI `--resolution` is fixed for Classic profiles.

---

## Still-open questions for other model

1. **Is CLI `--resolution` intentionally broken for Classic profiles, or a bug?**
   The flag is documented, the schema matches server expectations, the capability
   is enabled, but the CLI refuses locally. If a bug, worth filing upstream.

2. **What's the default synchronizer interval?** No docs mention it. Sample data
   suggests 5-15 min. Configurable at bootstrap? Per-stack? Where?

3. **Is direct REST use of `Client-ID: <arbitrary>` and inline `IdempotencyKey`
   safe for production CI?** What are the retry semantics if a 202 response is
   lost — will POSTing again with the same IdempotencyKey deduplicate?

4. **When `Action=revert` is chosen for one resource in a multi-resource
   observation, are other resources' drifts still open?** i.e., is the
   observation resolved partially per resource, or all-or-nothing?

5. **`GET /stacks/{stack}/changes-since-last-reconcile` — is this useful for a
   read-only PR eval that shows drift without creating a review?** Would avoid
   `stale-review` issues in the PR pipeline (which happens when multiple evals
   run without an intervening apply).

---

## Files created / touched this session

- `/tmp/formae-controls.json` — resolution controls (ObservationID + Decisions)
- `/tmp/forma.json` — pre-evaluated forma JSON (from `formae eval`)
- `/tmp/formae-swagger.json` — full agent swagger doc
- `part-2-agent-cicd/formae-0.90.0-open-questions.md` — this file
