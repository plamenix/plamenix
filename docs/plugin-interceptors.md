# Plugin interceptors — synchronous middleware

Interceptors let plugins block, mutate, or cancel a shell operation **before** it commits. They are the synchronous in-band counterpart to the [event bus](./plugin-events.md), which is asynchronous and notification-only.

This catalogue ports `PLUGIN_ARCHITECTURE.md` §8 into the docs tree.

## Why a separate surface

Events (`plamenix:cell/committed`) fire after state has changed and do not let subscribers cancel. Interceptors (`cell.committing`) run **before** the operation and the chain may refuse. Conflating the two breaks both contracts: subscribers expect fire-and-forget, interceptors expect "I can block this."

The pattern is canonical: Java Servlet Filters, Express/Koa middleware, Spring MVC `HandlerInterceptor`. Each registered handler receives a typed `Context` and returns `Continue` | `Replace(ctx')` | `Cancel(reason)`.

## Catalogue

| Extension point | Triggered by | Context | Plugin power |
|---|---|---|---|
| `query.executing` | Before any `db_execute` | `{sessionId, sql, profileId}` | Refuse destructive SQL, transform query, log to audit, attach context comments |
| `cell.committing` | Before inline cell edit commits | `{table, pk, column, oldValue, newValue}` | Validate (refuse bad data), transform (normalize format), audit-log |
| `row.inserting` | Before row insert | `{table, values}` | Validate FK constraints client-side, fill computed columns |
| `row.deleting` | Before row delete | `{table, pk}` | Refuse if dependencies, soft-delete vs hard-delete |
| `connection.opening` | Before connect attempt | `{config}` | Auth provider plugins mutate config (inject SSO token), refuse if policy violation |
| `export.starting` | Before export begins | `{format, scope, options}` | Add header rows, transform output, refuse if dataset too large |
| `editor.saving` | Before editor buffer "saved" event | `{tabId, buffer}` | SQL formatter plugins rewrite buffer in place |
| `schema.action-applying` | Before `RECREATE` / `DROP` / `ALTER` | `{action, target}` | Refuse high-risk operations in prod connections, require confirmation |

Adding a new extension point is SemVer-minor on the plugin API. Changing the shape of an existing point's `Context` is SemVer-major and ships under a new name (e.g. `query.executing.v2`).

## Chain semantics

### Ordering

Each plugin contribution declares a `priority` integer (default `100`, lower = earlier) OR topological hints (`before = "destructive-confirm"` / `after = "audit-log"`).

The host resolves the order at registration time:
1. Topological hints are honored when present; cycles refuse registration.
2. Ties broken by `priority` (ascending).
3. Final ties broken by plugin ID alphabetic (deterministic).

The resolved chain order is visible in the Permissions panel for any extension point that has more than one contributor.

### Decision values

```rust
pub enum Decision {
    /// Pass the (possibly mutated) context to the next interceptor.
    Continue,
    /// Replace the context entirely; subsequent interceptors see the new value.
    Replace(Context),
    /// Stop the chain. The operation is refused with `reason` shown to the user.
    Cancel { reason: String },
}
```

### Short-circuit on `Cancel`

When any interceptor returns `Cancel`, the host:
- Stops the chain immediately — later interceptors do not run.
- Aborts the underlying operation (no `db_execute`, no commit).
- Surfaces `reason` through the same channel the operation came from (toast for cell edits, error banner for queries, modal for schema actions).
- Fires the corresponding `*/failed` event (e.g. `plamenix:query/failed`) so subscribers see the abort.

### Replace propagation

`Replace(ctx')` is the *transform* path — formatter plugins rewriting SQL, audit plugins attaching trailing `-- audited` comments. Subsequent interceptors in the chain see the new context. Built-in interceptors (e.g. the destructive-DROP confirmation) see the final post-plugin form.

### Built-in interceptors

Several existing shell behaviours become first-party internal-server interceptors at well-known priorities:

| Priority | Built-in interceptor | Effect |
|---|---|---|
| `10` | `audit-tap` (when enabled) | Logs context to per-plugin audit sink, never blocks |
| `50` | `destructive-confirm` | Pops the "DROP / TRUNCATE / DELETE without WHERE" modal |
| `90` | `read-only-guard` | Refuses writes when the connection is flagged read-only |

User-registered plugins default to `priority = 100` and run after the built-ins. A plugin that explicitly wants to run before a built-in declares `before = "destructive-confirm"` and accepts the dependency contract.

### Timeout

The entire chain for a single operation is bounded by **500 ms wall-clock**. On overrun:
- Host aborts the chain.
- Operation proceeds **without further interception** (fail-open for safety — interactive UX takes precedence over interceptor completion).
- A `plamenix:plugin/interceptor-timeout` event fires with `{pluginId, extensionPoint}` so subscribers (and the operator) can attribute the slow handler.

This is the explicit opposite of fail-closed: refusing to operate when an interceptor hangs would make a single slow plugin a denial-of-service vector for the whole IDE.

### Trap + panic handling

If an interceptor's wasm code traps (OOM, fuel, epoch, divide-by-zero, host-import error):
- The trap is recorded against the offending plugin's crash budget per [crash isolation](./splash-window.md#crash-handling) (3 traps in 60s → DISABLED).
- The operation proceeds **without that interceptor**. Other interceptors in the chain continue.
- A `plamenix:plugin/crashed` event fires.

The chain is resilient to single-interceptor failure; only the offending plugin pays the cost.

## Wire

As shipped, in `plamenix:plugin@1.0.0`:

```wit
/// What an interceptor wants the host to do with the operation.
variant interception {
    proceed,
    replace(string),   // JSON context replacing the one handed in
    cancel(string),    // user-facing reason; never optional
}

intercept: func(point: string, context-json: string) -> interception;
```

One export, dispatched on the point name, sitting in the `plugin` interface next to `handle-event`.

### Why one export rather than eight

The original sketch gave each extension point its own named export and passed the context as a WIT `resource` with `get-field` / `set-field`. Three things argued against it once the surrounding code existed:

- **Adding an extension point is supposed to be SemVer-minor** (see above). With one export per point it is a change to the WIT contract, so every plugin's component shape shifts. With a dispatcher the host adds a point and no plugin is touched.
- **`handle-event` already established the pattern** — `func(topic, payload)`, one mandatory export, JSON-opaque payload, an empty body for plugins that registered nothing. A second, differently-shaped dispatch mechanism next to it would be two idioms for one job.
- **Host-owned resources are not used anywhere else in this host.** The `set-field` design also cannot express the transform path cleanly: the host would have to diff a mutated resource to discover what changed, where `replace(string)` states it outright.

What the resource design bought that this does not: field-level read-only enforcement. `sessionId` being gettable-but-not-settable is now a host-side check on the replacement context rather than something the type system refuses. That is a real reduction in guarantee and is written down here rather than glossed.

Exports are mandatory at the WIT level for both `handle-event` and `intercept`, for the same reason: a component's shape must not depend on what it registered at install time. A plugin that intercepts nothing returns `proceed`.

### One round trip per chain, not per plugin

The host runs the whole plugin segment of a chain in a single call (`run_chain`), applying priority order, replace propagation, and cancel short-circuit on its side. The renderer registers **one** handler per chain, in `plamenix-ui/src/interceptors/plugin-bridge.ts`.

The alternative — one renderer handler per plugin, so the TypeScript chain interleaves plugins with built-ins — costs a transport round trip per plugin inside a 500 ms budget that also has to cover the built-ins. The reserved priority band makes the interleaving moot anyway: plugins are confined to 100 and above and built-ins live below 100, so no plugin can be scheduled before a built-in. The case this cannot express is a plugin sitting *between* two built-ins, which nothing needs today.

### Manifest declaration

Plugins declare interceptor participation in their manifest:

```toml
[[contributions.interceptors]]
extension_point = "query.executing"
priority = 100
purpose = "Block destructive SQL against prod connections"
```

`purpose` is the rationale text shown in the Permissions panel + install dialog (Info.plist analog).

The host enforces, at manifest parse:
- `extension_point` must be one of the eight known points. A typo is refused with the valid set listed, because the failure mode otherwise is a handler that silently never runs.
- `priority` must be in `[100, 1000]`. `[0, 99]` is reserved for the host's own interceptors and a plugin cannot claim it — the read-only guard is not something a plugin gets to preempt. Defaults to `100`.
- The point's capability must be declared in `[permissions]`. This is the load-bearing one: an interceptor sees the context of every operation it intercepts, so registering for `cell.committing` without a write capability would read every value the user edits while showing an empty permissions dialog.
- `purpose` stays optional; the capability is what the host enforces.

`before` / `after` topological hints are **not implemented**. The chain resolves on `priority`, then plugin id — the id tie-break exists so two users with the same plugins get the same order regardless of what they installed first.

## Capability gates

Each extension point requires the relevant capability domain in `[permissions.required]`:

| Extension point | Required capability |
|---|---|
| `query.executing` | `db.read.any` (for inspection) OR `db.write.any` (to influence writes) |
| `cell.committing` | `db.write.any` |
| `row.inserting` / `row.deleting` | `db.write.any` |
| `connection.opening` | `db:session.context.read` AND domain-specific auth caps |
| `export.starting` | `db.read.any` |
| `editor.saving` | (no capability — editor is plugin-shared surface) |
| `schema.action-applying` | `db.write.any` |

A plugin requesting an interceptor without the corresponding capability is refused at install.

## Anti-patterns refused

- **Long-running work in an interceptor** — interceptors block the user operation. A plugin doing >100 ms of work in `query.executing` *will* be cancelled by the 500 ms chain budget. Long tasks go on the event bus + plugin's own async worker.
- **Network calls in an interceptor** — same reason. Auth provider plugins that need to refresh a token over HTTP do it eagerly on `connection.opening` only if the cached token expires, and they cache aggressively.
- **Reading other plugins' state** — `context` only exposes shell state and the current plugin's annotations. Cross-plugin coordination uses the event bus or shared commands.
- **Mutating non-mutable context fields** — host enforces. A plugin that calls `set-field("sessionId", "…")` on a read-only field gets `Err` back.
- **Returning `Cancel` without `reason`** — host refuses the manifest. Cancellations always carry a user-readable rationale.

## Comparison to events at a glance

| Aspect | Events (`*/ed`) | Interceptors (`*ing`) |
|---|---|---|
| Direction | Notification | Control |
| Timing | Post-commit | Pre-commit |
| Cancellable | No | Yes |
| Mutate input | No | Yes (`Replace`) |
| Ordering matters | No | Yes (priority + before/after) |
| Budget | None | 500 ms chain total |
| Trap handling | Plugin disabled, others continue | Operation proceeds without that interceptor |
| Subscription path | Manifest declaration | Manifest declaration |
| Wire | `event-bus.emit` / plugin `handle-event` | Per-point named WIT exports |

## Related

- [`plugin-events.md`](./plugin-events.md) — asynchronous notification surface (the `*ed` half)
- [`contribution-points.md`](./contribution-points.md) — declarative static surface
- [`plugin-system.md`](./plugin-system.md) — overall plugin architecture
- [`capability-model.md`](./capability-model.md) — permission grammar
- `../../PLUGIN_ARCHITECTURE.md` §8 — workspace-level design source
