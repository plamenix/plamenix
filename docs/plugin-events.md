# Plugin events — the dynamic surface

Plugins observe shell state changes through a typed event bus. Pair this document with [`plugin-interceptors.md`](./plugin-interceptors.md) (the synchronous middleware surface) and [`contribution-points.md`](./contribution-points.md) (the static surface). Together those three documents define the entire plugin–shell contract.

This catalogue ports `PLUGIN_ARCHITECTURE.md` §7 into the docs tree where decision records live.

## Naming convention

Hierarchical, reverse-DNS-style topics, period-separated within an area, slash-separated between area and entity:

```
<namespace>:<area>/<entity>.<verb>
```

| Namespace | Owner | Examples |
|---|---|---|
| `plamenix:*` | first-party shell | `plamenix:tab/opened` · `plamenix:query/executed` |
| `<plugin-id>:*` | plugin that emitted | `com.example.csv-export:job/completed` |

**Subscribers may glob**: `plamenix:editor/*` matches every `editor/...` topic; `plamenix:editor/cell.*` matches just cell events.

## Past-tense vs present-participle — discipline

| Suffix | Tense | Cancellable | Meaning |
|---|---|---|---|
| `*ed`, `*d` (`opened`, `committed`, `failed`) | Past | **No** | Event notification — state has already changed. Fire-and-forget. Plugins react. |
| `*ing` (`opening`, `committing`, `executing`) | Present-participle | **Yes** | Interceptor extension point (NOT an event). Synchronous, in-band, may mutate or short-circuit. See [`plugin-interceptors.md`](./plugin-interceptors.md). |

The split is load-bearing. An interceptor cannot become an event because it would no longer support `Cancel`. An event cannot become an interceptor because subscribers expect fire-and-forget delivery, not a chain that blocks the operation.

## Catalogue

### Lifecycle

| Topic | Payload | Notes |
|---|---|---|
| `plamenix:app/started` | `{}` | Fires once after boot completes (post `boot:ready`). |
| `plamenix:app/shutdown` | `{}` | Cancellable in interceptor form; see `app.shutdown-requesting`. |
| `plamenix:plugin/activated` | `{pluginId}` | Fires after the activated plugin returns `Ok` from `activate()`. |
| `plamenix:plugin/deactivated` | `{pluginId, reason}` | `reason ∈ {"unload", "uninstall", "permission-revoked", "host-shutdown"}`. |
| `plamenix:plugin/crashed` | `{pluginId, trap, willRestart}` | `trap` carries the wasmtime trap code; `willRestart` reflects the supervisor's decision per the plugin's restart policy. |

### Tabs + sessions

| Topic | Payload |
|---|---|
| `plamenix:tab/opened` | `{tabId}` |
| `plamenix:tab/activated` | `{tabId, previousTabId}` |
| `plamenix:tab/closed` | `{tabId}` |
| `plamenix:tab/renamed` | `{tabId, newTitle}` |

### Connection

| Topic | Payload | Notes |
|---|---|---|
| `plamenix:connection/opened` | `{sessionId, profile, engineVersion}` | `profile` carries enough metadata (host, db stem, user) to identify, never secrets. |
| `plamenix:connection/failed` | `{config, error}` | `config` redacts password + encryption-key fields. |
| `plamenix:connection/closed` | `{sessionId, reason}` | `reason ∈ {"user", "dead", "host-shutdown"}`. |
| `plamenix:connection/health-changed` | `{sessionId, health}` | `health ∈ {"healthy", "reconnecting", "dead", "unknown"}`. |

### Query execution

| Topic | Payload | Notes |
|---|---|---|
| `plamenix:query/executed` | `{sessionId, sql, outcomes, durationMs}` | Fires once per statement batch, post-commit. |
| `plamenix:query/failed` | `{sessionId, sql, error}` | Fires if execution raised any non-recovered error. |

### Row mutation

| Topic | Payload | Notes |
|---|---|---|
| `plamenix:cell/committed` | `{table, pk, column, oldValue, newValue}` | Inline edit applied. |
| `plamenix:row/inserted` | `{table, pk, values}` | `pk` may be empty array when the engine-assigned key cannot be predicted client-side. |
| `plamenix:row/deleted` | `{table, pk}` | Fires once per row in a bulk delete. |

### Schema

| Topic | Payload | Notes |
|---|---|---|
| `plamenix:schema/described` | `{sessionId, schema}` | Fires after a full `describe-schema` round-trip. |
| `plamenix:schema/action-applied` | `{sessionId, action, target}` | `action ∈ {"recreate", "drop", "alter", "create", "create-index", "recompute-statistics", …}`. |

### Export

| Topic | Payload |
|---|---|
| `plamenix:export/started` | `{exportId, format, scope}` |
| `plamenix:export/completed` | `{exportId, bytes, durationMs}` |
| `plamenix:export/failed` | `{exportId, error}` |

### Settings + theme

| Topic | Payload |
|---|---|
| `plamenix:settings/changed` | `{key, oldValue, newValue}` |
| `plamenix:theme/changed` | `{mode, accent}` |

### Editor

| Topic | Payload | Notes |
|---|---|---|
| `plamenix:editor/focused` | `{tabId}` | |
| `plamenix:editor/changed` | `{tabId, length}` | Debounced server-side at 200ms. |
| `plamenix:editor/selection-changed` | `{tabId, range}` | |
| `plamenix:editor/saved` | `{tabId}` | Fires after `editor.saving` interceptor chain completes. |

## Payload + schema discipline

Every event payload includes `schemaVersion: 1` as a mandatory field. Rules:

- **Adding** an optional payload field is SemVer-minor on the topic.
- **Renaming or removing** an existing field is SemVer-major → the new shape ships on a new topic (e.g. `plamenix:query/executed.v2`); the old topic stays for one minor release with the old payload so subscribers can migrate.
- Internal fields the host may need for debugging but plugins should not depend on are prefixed `_` and excluded from the SemVer contract.

## Wire

The plugin imports an `event-bus` interface (defined in `plamenix:plugin@1.0.0/plugin-integrated`):

```wit
interface event-bus {
    emit: func(topic: string, payload: string);
    // Subscriptions are declared via the plugin's manifest under
    // [[contributions.event_subscriptions]] and dispatched into the
    // plugin's exported handle-event(topic, payload) function.
}
```

### Subscription model

Plugins subscribe via manifest, not at runtime. This keeps subscription discoverable from the registry without instantiating the plugin:

```toml
[[contributions.event_subscriptions]]
topic = "plamenix:query/executed"
purpose = "Append query to audit log"
```

The host dispatches matching events to the plugin's exported `handle-event(topic: string, payload: string)`. Subscriptions auto-clean on `deactivate()` per the OTP-style supervisor cleanup.

Capability `event:subscribe:<channel>` gates the subscription declaration; manifests that subscribe to `plamenix:cell/committed` must request `event:subscribe:plamenix:cell.committed`.

### Publishing

Publishing is runtime via the imported `event-bus.emit(topic, payload)`. Plugins may only publish to their own namespace (`<plugin-id>:*`) unless they hold an explicit `event:publish:<channel>` capability for the foreign topic.

## Anti-patterns refused

- **Re-firing past events for late subscribers** — events are forward-only. Plugins that need historical state ask the host through a query API, never via the bus.
- **Publishing internal domain events** — only integration events cross the plugin boundary. Internal Zustand store changes never become public topics.
- **Synchronous subscribers** — subscribers are notified, they cannot block the publisher. Use interceptors when you need to block.
- **Plugin-to-plugin direct invocation** — plugins coordinate via events on namespaced topics, never via direct WIT calls. Cross-plugin coupling stays loose.

## Related

- [`plugin-interceptors.md`](./plugin-interceptors.md) — synchronous middleware (the `*ing` half of the surface)
- [`contribution-points.md`](./contribution-points.md) — declarative static surface
- [`plugin-system.md`](./plugin-system.md) — overall plugin architecture (WASM Component Model, ESM contributions)
- [`capability-model.md`](./capability-model.md) — permission grammar including `event:*` capabilities
- `../../PLUGIN_ARCHITECTURE.md` §7 — workspace-level design source
