# Plugin events — the dynamic surface

Plugins observe shell state changes through a typed event bus. Pair this document with [`plugin-interceptors.md`](./plugin-interceptors.md) (the synchronous middleware surface) and [`contribution-points.md`](./contribution-points.md) (the static surface). Together those three documents define the entire plugin–shell contract.

This catalogue ports `PLUGIN_ARCHITECTURE.md` §7 into the docs tree where decision records live.

## Two buses, and which one you are on

There are two event buses, and the distinction decides whether a
subscription of yours will ever fire.

| Bus | Where | Who subscribes | How a topic gets there |
|---|---|---|---|
| **UI bus** | `plamenix-ui`, TypeScript, in the browser/WebView | UI contributions and React panels | `emit*` helpers in `plamenix-ui/src/events/` |
| **Host bus** | `plamenix-plugin-host`, Rust | **WASM plugins**, via `handle-event` | the shell calling `emit_event` / `emitEvent` |

The catalogue below is the **UI bus**. Almost none of it reaches WASM
plugins today.

> **Every topic in this catalogue reaches WASM plugins.** The shell
> forwards them from the UI bus to the host bus, so a manifest
> subscription for any topic below is dispatched to `handle-event`.
>
> Forwarding is **selective**: the shell asks the host which patterns
> anything is subscribed to and sends only matching topics. Most of
> these events originate in the renderer, so reaching a plugin costs a
> round trip — a Tauri command on desktop, an HTTP request on web — and
> `editor/changed` fires as the user types. With no plugin subscribed,
> which is the usual case, nothing goes on the wire.
>
> Two consequences worth knowing. A payload has to survive
> `JSON.stringify`, and one that cannot — a cycle, a `BigInt` — is
> dropped with a warning rather than delivered. And payloads are capped
> at 64 KiB; an oversized one is refused before the round trip rather
> than by the host.

## Naming convention

Slash-separated `<area>/<entity>` topics. Subscribers may glob: `editor/*`
matches every `editor/...` topic, and `**` matches zero or more trailing
segments.

| Namespace | Owner | Example |
|---|---|---|
| *(unprefixed)* | first-party shell | `tab/opened` · `query/executed` |
| `<plugin-id>:` | plugin that emitted it | `com.example.csv-export:job/completed` |

The plugin prefix is **enforced, not a convention**: a plugin publishing
under its own id needs no capability, because that namespace is its own
by construction. Publishing anywhere else requires
`event.publish.<channel>` for the topic's first segment, so a plugin
cannot forge a shell event without a grant naming the area it is
forging into.

Shell topics carry no prefix. This document used to show them as
`plamenix:tab/opened`; nothing emitted that, and the bus splits patterns
on `/` only, so `plamenix:*` was a single literal segment that matched
nothing at all.

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
| `app/started` | `{}` | Fires once after boot completes (post `boot:ready`). |
| `app/shutdown` | `{}` | Cancellable in interceptor form; see `app.shutdown-requesting`. |
| `plugin/activated` | `{pluginId}` | Fires after the activated plugin returns `Ok` from `activate()`. |
| `plugin/deactivated` | `{pluginId, reason}` | `reason ∈ {"unload", "uninstall", "permission-revoked", "host-shutdown"}`. |
| `plugin/crashed` | `{pluginId, trap, willRestart}` | `trap` carries the wasmtime trap code; `willRestart` reflects the supervisor's decision per the plugin's restart policy. |

### Tabs + sessions

| Topic | Payload |
|---|---|
| `tab/opened` | `{tabId}` |
| `tab/activated` | `{tabId, previousTabId}` |
| `tab/closed` | `{tabId}` |
| `tab/renamed` | `{tabId, newTitle}` |

### Connection

| Topic | Payload | Notes |
|---|---|---|
| `connection/opened` | `{sessionId, profile, engineVersion}` | `profile` carries enough metadata (host, db stem, user) to identify, never secrets. |
| `connection/failed` | `{config, error}` | `config` redacts password + encryption-key fields. |
| `connection/closed` | `{sessionId, reason}` | `reason ∈ {"user", "dead", "host-shutdown"}`. |
| `connection/health-changed` | `{sessionId, health}` | `health ∈ {"healthy", "reconnecting", "dead", "unknown"}`. |

### Query execution

| Topic | Payload | Notes |
|---|---|---|
| `query/executed` | `{sessionId, sql, outcomes, durationMs}` | Fires once per statement batch, post-commit. |
| `query/failed` | `{sessionId, sql, error}` | Fires if execution raised any non-recovered error. |

### Row mutation

| Topic | Payload | Notes |
|---|---|---|
| `cell/committed` | `{table, pk, column, oldValue, newValue}` | Inline edit applied. |
| `row/inserted` | `{table, pk, values}` | `pk` may be empty array when the engine-assigned key cannot be predicted client-side. |
| `row/deleted` | `{table, pk}` | Fires once per row in a bulk delete. |

### Schema

| Topic | Payload | Notes |
|---|---|---|
| `schema/described` | `{sessionId, schema}` | Fires after a full `describe-schema` round-trip. |
| `schema/action-applied` | `{sessionId, action, target}` | `action ∈ {"recreate", "drop", "alter", "create", "create-index", "recompute-statistics", …}`. |

### Editor

| Topic | Payload |
|---|---|
| `editor/changed` | `{tabId, sql}` |
| `editor/focused` | `{tabId, focusedAt}` |
| `editor/saved` | `{tabId, sql, savedAt}` |
| `editor/selection-changed` | `{tabId, from, to}` |

### Export

| Topic | Payload |
|---|---|
| `export/started` | `{exportId, format, scope}` |
| `export/completed` | `{exportId, bytes, durationMs}` |
| `export/failed` | `{exportId, error}` |

### Settings + theme

| Topic | Payload |
|---|---|
| `settings/changed` | `{key, oldValue, newValue}` |
| `theme/changed` | `{mode, accent}` |

### Editor

| Topic | Payload | Notes |
|---|---|---|
| `editor/focused` | `{tabId}` | |
| `editor/changed` | `{tabId, length}` | Debounced server-side at 200ms. |
| `editor/selection-changed` | `{tabId, range}` | |
| `editor/saved` | `{tabId}` | Fires after `editor.saving` interceptor chain completes. |

## Payload + schema discipline

Every event payload includes `schemaVersion: 1` as a mandatory field. Rules:

- **Adding** an optional payload field is SemVer-minor on the topic.
- **Renaming or removing** an existing field is SemVer-major → the new shape ships on a new topic (e.g. `query/executed.v2`); the old topic stays for one minor release with the old payload so subscribers can migrate.
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

Plugins subscribe via the manifest, not at runtime, so a subscription is
discoverable from the registry without instantiating the plugin. It is a
flat list of topics under `[contributions]`:

```toml
[contributions]
event_subscriptions = ["query/executed"]
```

The host dispatches matching events to the plugin's exported
`handle-event(topic: string, payload: string)`. Subscriptions are
withdrawn when the plugin deactivates.

**Subscription is not gated by a capability.** There is no
`event.subscribe.*` in the grammar and nothing checks one. Any plugin
may declare any topic. That is defensible rather than accidental — the
host only ever dispatches what it chooses to dispatch, and a payload
contains what the shell decided to publish — but it does mean a
subscription list is not a permission boundary, and the install dialog
should not be read as though it were.

Earlier revisions of this document described a
`[[contributions.event_subscriptions]]` table array with `topic` and
`purpose` fields, gated by a capability spelled
`event:subscribe:<channel>`. None of the three existed.

### Publishing

Publishing is runtime via the imported `event-bus.emit(topic, payload)`. Plugins may only publish to their own namespace (`<plugin-id>:*`) unless they hold an `event.publish.<channel>` capability naming the topic's first segment.

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
