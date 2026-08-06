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

```wit
interface interceptor {
    resource context {
        get-field: func(name: string) -> option<string>;
        set-field: func(name: string, value: string);
    }

    enum decision-kind { continue, cancel }
    record decision {
        kind: decision-kind,
        reason: option<string>,  // populated when kind = cancel
    }
}

// Plugins implement one export per extension point they participate in.
// The host calls these by name on the plugin's component instance.
export query-executing:        func(ctx: borrow<context>) -> interceptor.decision;
export cell-committing:        func(ctx: borrow<context>) -> interceptor.decision;
export row-inserting:          func(ctx: borrow<context>) -> interceptor.decision;
export row-deleting:           func(ctx: borrow<context>) -> interceptor.decision;
export connection-opening:     func(ctx: borrow<context>) -> interceptor.decision;
export export-starting:        func(ctx: borrow<context>) -> interceptor.decision;
export editor-saving:          func(ctx: borrow<context>) -> interceptor.decision;
export schema-action-applying: func(ctx: borrow<context>) -> interceptor.decision;
```

Plugins implement only the exports for points they want to participate in; the others are no-ops the host never calls.

### Context as a resource handle

`context` is a WIT `resource` rather than a plain record so the host can:
- Add new fields without recompiling plugins (lifetime-attached, host-owned).
- Enforce read-only views on fields the plugin should not mutate (`sessionId` is gettable but not settable).
- Garbage-collect context state when the chain completes (no plugin-side leaks).

`borrow<context>` gives the plugin temporary access; on chain completion the host drops the resource.

### Manifest declaration

Plugins declare interceptor participation in their manifest:

```toml
[[contributions.interceptors]]
extension_point = "query.executing"
priority = 100
purpose = "Block destructive SQL against prod connections"
```

`purpose` is the rationale text shown in the Permissions panel + install dialog (Info.plist analog).

The host enforces:
- `extension_point` must be one of the known points (typo refused at install).
- `priority` is an integer in `[0, 1000]`. Reserve `[0, 99]` for first-party built-ins.
- `purpose` non-empty for marketplace plugins; warning-only for sideload.

## Capability gates

Each extension point requires the relevant capability domain in `[permissions.required]`:

| Extension point | Required capability |
|---|---|
| `query.executing` | `db:query.read` (for inspection) OR `db.write:execute` (to influence writes) |
| `cell.committing` | `db.write:execute` |
| `row.inserting` / `row.deleting` | `db.write:execute` |
| `connection.opening` | `db:session.context.read` AND domain-specific auth caps |
| `export.starting` | `db:query.read` |
| `editor.saving` | (no capability — editor is plugin-shared surface) |
| `schema.action-applying` | `db.write:execute` |

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
