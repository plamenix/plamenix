# Plamenix Plugin Architecture

**Status**: Adopted 2026-05-27. Full plugin suite scoped to M1 per [`../MILESTONES.md`](../MILESTONES.md). Live implementation tracker at `../../PLUGIN_TRACKER.md` (workspace-level).

**Canonical location**: this file (`plamenix/docs/plugin-architecture.md`). The workspace-level `../../PLUGIN_ARCHITECTURE.md` is a pointer to it, not a copy — the workspace root is untracked, and the mirror it used to hold had already drifted.

Synthesized from research on VSCode, JetBrains, Theia, Zed, Atom (failure), Obsidian (anti-pattern), Eclipse OSGi, Erlang/OTP, Hexagonal Architecture, Microkernel pattern (POSA), Event-Driven Architecture (Fowler), Interceptor pattern, Object Capability Model, WASM Component Model, WASI Preview 2, Manifest V3, Deno permissions.

Owner: Zlatan Omerović / Ascent Systèmes.

---

## 0. Why this document exists

`docs/plugin-system.md` commits "first-class plugins from 1.0.0-beta." Current code ships ~25% of that promise: host runtime works, one demo plugin loads, sidebar-panel contribution is the only consumed surface. The remaining 75% has to be designed coherently, not bolted on.

This document is the design target. It is not a tutorial, not a roadmap. Implementation phasing is the last section.

---

## 1. Five foundational commitments

These are the non-negotiable design axes. Every later decision derives from these.

1. **Microkernel core + internal servers + external servers.** The host is a minimal facade over mechanism only — discovery, lifecycle, dispatch, capability gating. First-party features (BLOB renderer, CSV export, Firebird tip pack) are *internal servers*: same plugin contract, shipped in-binary, dogfooding the contract on every release. Third-party plugins are *external servers*. This symmetry is the only honest way to keep the contract from rotting.

2. **Hexagonal ports = the WIT contract.** Plugin *exports* are driving ports (the host calls into them when it needs a contribution). Plugin *imports* are driven ports (the plugin calls the host when it needs a service). Capabilities are enforced at the driven-port boundary: if the manifest didn't request it, the host doesn't link it. Object Capability Model by construction — no ambient authority.

3. **Two-layer extension surface.** *Static contributions* declared in the manifest (host reads at startup without loading plugin code). *Dynamic API* runtime register/listen/emit calls plugin code makes after activation. Both required. Atom failed because it had only dynamic; pure-static is too rigid for live workflows.

4. **Default deny, granular grants, per-call attenuation.** Capabilities are `domain:verb:scope` triples. Plugins request the minimum they need. Required capabilities consent at install time (MV3 style). Optional capabilities prompt at first use (iOS/Chrome style). Capabilities returning host objects return *resource handles*, not ambient pointers — a plugin granted `db:query` for connection X cannot reach connection Y.

5. **OTP-style supervision over wasmtime stores.** One Engine across the host (JIT cache reuse); one `Store<PluginCtx>` per plugin instance (isolation). Crashes manifest as `Trap`; supervisor applies restart policy with intensity bounds (3 traps in 60s → auto-disable). The store-per-plugin pattern is the only structural way to get crash containment from wasmtime, since instances cannot deallocate until their Store drops.

---

## 2. Architectural layers (what owns what)

```
┌─────────────────────────────────────────────────────────────────┐
│ PLAMENIX SHELL (UI + IDE chrome)                                │
│  ├ Internal servers (first-party plugins, baked in-binary)      │
│  └ Consumers: result table, editor, schema browser, exports…    │
└──────────────────┬─────────────────────────┬────────────────────┘
                   │                         │
       ┌───────────▼───────────┐ ┌───────────▼───────────┐
       │ CONTRIBUTION REGISTRY │ │ EVENT BUS             │
       │ (static surface)      │ │ (dynamic surface)     │
       │ - per contribution    │ │ - integration events  │
       │   point, plugins map  │ │ - hierarchical topics │
       │   to slot entries     │ │ - past-tense          │
       └───────────┬───────────┘ └───────────┬───────────┘
                   │                         │
       ┌───────────▼─────────────────────────▼───────────┐
       │ INTERCEPTOR CHAINS                              │
       │ (synchronous middleware per extension point:    │
       │  beforeQuery, beforeCellCommit, etc.)           │
       └───────────┬─────────────────────────────────────┘
                   │
       ┌───────────▼─────────────────────────────────────┐
       │ SUPERVISOR                                       │
       │ (lifecycle, restart policy, intensity bounds)   │
       └───────────┬─────────────────────────────────────┘
                   │
       ┌───────────▼─────────────────────────────────────┐
       │ WASMTIME ENGINE (1)                              │
       │  Store<PluginCtx> per plugin instance (N)        │
       │  WIT contract = hexagonal port catalog           │
       │  Capability-gated imports                        │
       └─────────────────────────────────────────────────┘
```

Each layer has one concern. Crossing them is forbidden:
- Registry doesn't know about events
- Events don't know about interceptors
- Interceptors don't know about supervision
- Supervisor doesn't know about contribution semantics

Layer composition is glue code in the microkernel. Plugins see only the WIT contract.

---

## 3. Plugin lifecycle state machine

Composed from OSGi (six structural states) + OTP (restart policy decisions) + Plamenix-specific (signature/capability verification):

```
                ┌──────────────┐
                │ DISCOVERED   │  manifest parsed, signature unverified
                └──────┬───────┘
                       │ verify signature + capability syntax
                       ▼
                ┌──────────────┐
                │ INSTALLED    │  manifest valid, code stored on disk
                └──────┬───────┘
                       │ resolve WIT imports against host SPI
                       │ check capability grants
                       ▼
                ┌──────────────┐
                │ RESOLVED     │  imports satisfied, capabilities granted
                └──────┬───────┘
                       │ start() → instantiate Store, link imports
                       ▼
                ┌──────────────┐
                │ STARTING     │  running activate(), registering services
                └──────┬───────┘
                       │ activate returns Ok
                       ▼
                ┌──────────────┐
       ┌───────▶│ ACTIVE       │  accepting calls, contributing to slots
       │        └──────┬───────┘
       │               │ stop() OR trap OR fuel-exhaustion
       │               │     OR capability-revoked OR shutdown
       │               ▼
       │        ┌──────────────┐
       │        │ STOPPING     │  running deactivate(), unregistering
       │        └──────┬───────┘
       │               │ deactivate returns OR timeout
       │               ▼
       │        ┌──────────────┐
       └────────│ STOPPED      │  same as RESOLVED + clean shutdown
                └──────┬───────┘
                       │ uninstall()
                       ▼
                ┌──────────────┐
                │ UNINSTALLED  │  terminal; references unusable
                └──────────────┘

Crash path: ACTIVE --trap--> [CRASHED handled by supervisor]
  → restart? (transient policy + intensity not exhausted) → STARTING
  → disable? (intensity exhausted) → DISABLED (Permissions panel shows)
```

Restart policies per plugin (manifest field `restart_policy`):
- `permanent` — always restart (only for first-party essential plugins, e.g. core BLOB renderer)
- `transient` — restart on abnormal exit only (DEFAULT for community plugins)
- `temporary` — never restart (one-shot tools, batch imports)

Intensity bound: max N restarts in window W. Default `N=3, W=60s`. On exceed → `DISABLED`. UI shows reason. User can re-enable manually.

---

## 4. WIT worlds — capability tiers

Rather than one monolithic WIT world per host, ship a tiered set. Each plugin declares which world it targets; host links only the matching imports. This is OCap enforced at the type level: a plugin targeting `plamenix:plugin-minimal` cannot even *attempt* to call `db.query` because the import doesn't exist in its world.

```wit
// crates/plamenix-plugin-host/wit/

package plamenix:plugin@1.0.0;

// Tier 0: zero capabilities. UI-only plugins (themes, tip packs).
world plugin-minimal {
  import log: func(level: log-level, msg: string);
  import host-version: func() -> string;
  export activate: func() -> activation-result;
  export deactivate: func();
}

// Tier 1: read-only DB access. Cell renderers, formatters, object inspectors.
world plugin-db-reader {
  include plugin-minimal;
  import db: interface { /* describe-schema, current-session, current-row */ };
}

// Tier 2: read+write DB. Bulk-edit plugins, data generators.
world plugin-db-writer {
  include plugin-db-reader;
  import db-write: interface { /* execute (with capability check), tx-* */ };
}

// Tier 3: full IDE integration. Auth providers, export plugins.
world plugin-integrated {
  include plugin-db-writer;
  import fs: interface  { /* preopened plugin-data dir */ };
  import net: interface { /* host allow-list */ };
  import settings: interface { /* per-plugin scope */ };
  import event-bus: interface { /* emit/subscribe */ };
}

// Tier-orthogonal capabilities, requested explicitly per plugin:
//   keyring, clipboard, notify (desktop-only)
//   server-routes (web-only, future)
```

Plugin authors pick the smallest world that fits. Manifest enforces:

```toml
[plugin]
world = "plamenix:plugin@1.0.0/plugin-db-reader"
```

Host refuses to load plugins whose declared world it doesn't recognize. Adding a new world is a SemVer-minor host change; modifying an existing world's shape is SemVer-major.

---

## 5. Capability grammar

All capabilities are `domain:verb[:scope]` triples. Finite, host-enforced through WIT worlds + runtime gating. No wildcards (refuse manifests requesting `<all_urls>`-style unbounded).

| Domain | Verb examples | Scope examples | Edition | Notes |
|---|---|---|---|---|
| `db` | `schema.list`, `schema.describe`, `query.read` | `connection:current`, `database:<name>` | U | Returns connection resource handle |
| `db.write` | `execute`, `tx.begin`, `tx.commit`, `tx.rollback` | per-call handle | U | Capability checked at every call; UI banner shown on first use |
| `db.session` | `context.read` | per-tab | U | Read current sessionId, schema, focused cell |
| `fs` | `read`, `write` | `plugin-data` (default), `workspace` (optional) | U | No absolute paths. WASI preopens enforce scope. |
| `net` | `fetch.https` | host:port allow-list | U | Deno-style allow-list. `*.example.com` allowed but flagged. |
| `secrets` | `read`, `write` | `service:<key>` | D | OS keychain. Web edition: no equivalent → capability refused at install |
| `clipboard` | `read`, `write` | always per-call prompt | U | First-use prompt always (per Chrome/iOS pattern) |
| `notify` | `display` | global | D | OS notification. Web: in-browser toast equivalent |
| `event` | `publish.<channel>`, `subscribe.<channel>` | namespaced channels | U | `plugin.<id>.*` (plugin-owned) vs `shell.*` (shell-emitted) |
| `settings` | `read`, `write` | own-plugin scope only | U | No cross-plugin settings reads |
| `theme` | `register` | global | U | Static — manifest declares themes, no runtime API needed |
| `command` | `register`, `invoke` | namespaced commands | U | Plugins can call other plugins' commands if both opted-in |

**Intentionally absent (no escape hatch ever)**:
- `process` — no shell-out. If a plugin needs an external tool, a first-party companion binary handles it through a narrow host-mediated interface.
- `fs:host` — no access to user's general filesystem. `workspace` scope is the project root, granted optionally.
- `db:any-connection` — every DB capability is per-connection or per-session.

**Required vs optional split**:
```toml
[permissions.required]
db = ["schema.list"]
fs = ["read:plugin-data"]

[permissions.optional]
fs = ["write:workspace"]
net = ["fetch.https:api.example.com:443"]
```

Required = batch consent on install (single screen). Optional = first-use prompt with three buttons (Allow once / Allow always / Deny).

**Purpose strings (Info.plist analog)** — every capability declaration should carry a one-line `purpose` field. Optional: `plamenix-cli validate` warns on a missing one, and the install dialog shows the capability without a rationale. The capability itself is what the host enforces.

```toml
[[permissions.optional.fs]]
scope = "workspace"
purpose = "Save exported CSV to your project"
```

---

## 6. Contribution points catalog (the static surface)

Each contribution point has a manifest field, a shell consumer location, and a typed WIT export the plugin implements. Built-in features ship as internal servers that register through the same registry — VSCode model.

| Point | Manifest field | Shell consumer | What plugins provide |
|---|---|---|---|
| `commands` | `[[contributions.commands]]` | Command palette + keybindings + menus | Imperative actions with stable IDs |
| `keybindings` | `[[contributions.keybindings]]` | Global keymap | Key chord → command |
| `menus` | `[[contributions.menus.<location>]]` | Context menus on rows/objects/cells/tabs | Menu items conditional on `when` clauses |
| `cell_renderers` | `[[contributions.cell_renderers]]` | `ResultTable.CellContent` dispatcher | Renderer for `(columnType, mimeType, predicate)` |
| `cell_editors` | `[[contributions.cell_editors]]` | Inline-edit dispatcher | Editor widget for same selector |
| `export_formats` | `[[contributions.export_formats]]` | Export toolbar + DatabaseExportModal | Format ID, label, MIME, handler |
| `import_sources` | `[[contributions.import_sources]]` | Import wizard (new) | Source ID, file-picker filter, handler |
| `sidebar_panels` | `[[contributions.sidebar_panels]]` | PluginsSidebar | Panel ID, label, icon, React component slot |
| `toolbar_buttons` | `[[contributions.toolbar_buttons]]` | StatusBar / TabStrip toolbar | Button ID, icon, command |
| `object_inspectors` | `[[contributions.object_inspectors]]` | SchemaBrowser node-click + ObjectListPage | Per entity kind: tabs in inspector view |
| `schema_actions` | `[[contributions.schema_actions]]` | Schema action menu | Action ID, label, applicable kinds, handler |
| `sql_formatters` | `[[contributions.sql_formatters]]` | DDL viewer + editor "Format buffer" command | Formatter ID, dialect, handler |
| `auth_providers` | `[[contributions.auth_providers]]` | ConnectionScreen alt-auth tabs | Provider ID, fields schema, login handler |
| `tip_packs` | `[[contributions.tip_packs]]` | WelcomeDashboard `TipsCard` | Tip catalog (list of `{id, text, link?, version-min?}`) |
| `themes` | `[[contributions.themes]]` | useThemeStore | Theme ID, CSS variable overrides |
| `settings_panels` | `[[contributions.settings_panels]]` | SettingsPanel section iteration | Panel ID, fields schema |
| `dashboard_sections` | `[[contributions.dashboard_sections]]` | StatsDashboard | Section ID, title, React slot, refresh handler |
| `status_bar_items` | `[[contributions.status_bar_items]]` | StatusBar | Item ID, alignment, priority, React slot |
| `completion_providers` | `[[contributions.completion_providers]]` | SqlEditor CodeMirror autocomplete | Per language (`firebird-sql`), provider returns completions for context |
| `diagnostics_providers` | `[[contributions.diagnostics_providers]]` | SqlEditor linter gutter (new) | Provider returns diagnostics for current buffer |

**Manifest example (a cell renderer plugin)**:

```toml
[plugin]
id = "com.example.json-cell-renderer"
name = "JSON Cell Renderer"
version = "1.0.0"
plamenix_min_version = ">=1.0.0-beta"
plugin_api = "1.0"
world = "plamenix:plugin@1.0.0/plugin-minimal"
targets = ["desktop", "web"]
restart_policy = "transient"

[[contributions.cell_renderers]]
id = "json-tree"
label = "JSON Tree"
predicate = { column_type = "VARCHAR", value_pattern = "^\\s*[{[]" }
priority = 100
```

Built-in BLOB renderer ships as an internal server with the same shape — manifest baked into the host binary, registered at boot.

---

## 7. Event catalog (the dynamic surface — `onDid*` / `onWill*`)

Hierarchical topic naming: `plamenix:<area>/<entity>.<verb>`. First-party namespace is `plamenix:*`; plugin-owned is `<plugin-id>:*`. Subscribers can use globs: `plamenix:editor/*` or `plamenix:editor/cell.*`.

Discipline:
- **`onDid*`** (past-tense, non-cancellable) = event notification. Fire-and-forget. Fired post-commit. Plugins react.
- **`onWill*`** (present-participle, cancellable) = interceptor extension point (see §8). Synchronous, in-band, may mutate or short-circuit.

### Lifecycle
- `plamenix:app/started`
- `plamenix:app/shutdown` (cancellable via interceptor)
- `plamenix:plugin/activated` `{pluginId}`
- `plamenix:plugin/deactivated` `{pluginId, reason}`
- `plamenix:plugin/crashed` `{pluginId, trap, willRestart}`

### Tabs + sessions
- `plamenix:tab/opened` `{tabId}`
- `plamenix:tab/activated` `{tabId, previousTabId}`
- `plamenix:tab/closed` `{tabId}`
- `plamenix:tab/renamed` `{tabId, newTitle}`

### Connection
- `plamenix:connection/opening` (interceptor — `onWill`)
- `plamenix:connection/opened` `{sessionId, profile, engineVersion}`
- `plamenix:connection/failed` `{config, error}`
- `plamenix:connection/closed` `{sessionId, reason}`
- `plamenix:connection/health-changed` `{sessionId, health}`

### Query execution
- `plamenix:query/executing` (interceptor — `onWill`, can cancel destructive statements)
- `plamenix:query/executed` `{sessionId, sql, outcomes, durationMs}`
- `plamenix:query/failed` `{sessionId, sql, error}`

### Row mutation
- `plamenix:cell/committing` (interceptor — `onWill`, can validate or transform)
- `plamenix:cell/committed` `{table, pk, column, oldValue, newValue}`
- `plamenix:row/inserted` `{table, pk, values}`
- `plamenix:row/deleted` `{table, pk}`

### Schema
- `plamenix:schema/described` `{sessionId, schema}`
- `plamenix:schema/action-applied` `{sessionId, action, target}` (RECREATE, ALTER, DROP, etc.)

### Export
- `plamenix:export/started` `{exportId, format, scope}`
- `plamenix:export/completed` `{exportId, bytes, durationMs}`
- `plamenix:export/failed` `{exportId, error}`

### Settings + theme
- `plamenix:settings/changed` `{key, oldValue, newValue}`
- `plamenix:theme/changed` `{mode, accent}`

### Editor
- `plamenix:editor/focused` `{tabId}`
- `plamenix:editor/changed` `{tabId, length}` (debounced)
- `plamenix:editor/selection-changed` `{tabId, range}`
- `plamenix:editor/saving` (interceptor — `onWill`, lets formatter plugins rewrite buffer)
- `plamenix:editor/saved` `{tabId}`

**Payload shape**: every event includes `{schemaVersion: 1, ...}`. Schema bumps add `v2` topic alongside; old topic kept for one minor release for backward compat.

**Wire**: WIT exports `event.subscribe(topic-pattern, callback)` returns a subscription handle; plugin holds it. On `deactivate`, all subscriptions auto-disposed by host (OTP-style supervisor cleanup).

---

## 8. Interceptor chains (the synchronous middleware)

Distinct from events: interceptors are synchronous, in-band, can mutate or short-circuit. The host wraps each core operation through an ordered chain of plugin-registered handlers.

Pattern from Java Servlet Filters + Express middleware. Each interceptor sees a typed `Context` and returns `Continue` | `Replace(newContext)` | `Cancel(reason)`.

### Interceptor extension points

| Extension point | Triggered by | Context | Plugin power |
|---|---|---|---|
| `query.executing` | Before any `db_execute` | `{sessionId, sql, profileId}` | Refuse destructive SQL, transform query, log to audit, attach context comments |
| `cell.committing` | Before inline cell edit commits | `{table, pk, column, oldValue, newValue}` | Validate (refuse bad data), transform (normalize format), audit-log |
| `row.inserting` | Before row insert | `{table, values}` | Validate FK constraints client-side, fill computed columns |
| `row.deleting` | Before row delete | `{table, pk}` | Refuse if dependencies, soft-delete vs hard-delete |
| `connection.opening` | Before connect attempt | `{config}` | Auth provider plugins mutate config (inject SSO token), refuse if policy violation |
| `export.starting` | Before export begins | `{format, scope, options}` | Add header rows, transform output, refuse if dataset too large |
| `editor.saving` | Before editor buffer "saved" event | `{tabId, buffer}` | SQL formatter plugins rewrite buffer in place |
| `schema.action-applying` | Before RECREATE / DROP / ALTER | `{action, target}` | Refuse high-risk operations in prod connections, require confirmation |

### Chain semantics

- **Ordering** declared via `priority` (lower number = earlier) OR via `before`/`after` topological hints. Default priority `100`.
- **Short-circuit on Cancel**: when an interceptor returns `Cancel(reason)`, no subsequent interceptors run, the operation is aborted, user sees `reason`.
- **Replace propagation**: when an interceptor returns `Replace(ctx')`, subsequent interceptors see the mutated context.
- **Built-in interceptors** ship as internal servers at well-known priorities (the existing "destructive DROP confirmation" UX becomes a built-in `query.executing` interceptor at priority 50).
- **Timeout**: interceptor chain bounded by 500ms total wall-clock. Exceeded → chain aborted, operation proceeds without further interception (fail-open for safety).
- **Failures**: if an interceptor traps (wasm Trap, panic), the offending plugin is recorded against its crash budget; operation proceeds without that interceptor.

### Wire

WIT:
```wit
interface interceptor {
  resource context {
    get-field: func(name: string) -> option<string>;
    set-field: func(name: string, value: string);
  }
  enum decision { continue, cancel }
  type result = tuple<decision, option<string>>;  // (decision, reason if cancel)
}

// Plugins implement exports for each interceptor point they participate in
export query-executing: func(ctx: borrow<context>) -> interceptor.result;
```

---

## 9. Resource limits

Per-plugin defaults. Manifest can request elevation with explicit capability + UI warning.

| Limit | Default | Mechanism | Notes |
|---|---|---|---|
| Memory | 64 MiB | `ResourceLimiter::memory_growing` cap | Plugin sees `out-of-memory` trap if it grows past |
| Linear memory tables | 10 000 entries | `ResourceLimiter::table_growing` | Default reasonable |
| Sub-instances / tables / memories | 16 each | `ResourceLimiter::{instances,tables,memories}` | Plugins shouldn't spawn sub-instances |
| Stack | 512 KiB | `Config::max_wasm_stack` | Default; overflow traps cleanly |
| CPU per host call (interactive) | 100 ms | `Config::epoch_interruption(true)` + per-store deadline | Tick every 10ms |
| CPU per host call (background) | 5 s | Higher epoch deadline for "background_task" capability | Plugins must request elevation |
| Concurrent in-flight calls per plugin | 4 | Tokio semaphore per plugin | Backpressure beyond |
| Disk per plugin | 64 MiB | OS-level quota on `~/.plamenix/plugins/<id>/data/` | Enforced via filesystem driver, not WASI |
| Network requests per minute | 60 | Host-side rate limiter | Surface 429 to plugin |

Fuel-based limits (`Config::consume_fuel`) are NOT used. Fuel gives determinism we don't need and overhead we do feel. Epoch is the right choice for an IDE.

### The host embedding has to cooperate

Epoch preemption only works if the ticker runs on a **different thread** from the call it is policing. The ticker is a Tokio task; a plugin spinning inside wasm holds its thread without yielding, so on a current-thread runtime the ticker is never scheduled, the epoch never advances, and the call runs forever. The symptom is a pegged core, not a timeout.

Both shells satisfy this today — Tauri and napi-rs each run a multi-threaded Tokio runtime — but it is a property of the *embedding*, not of `plamenix-plugin-host`. Any new host that embeds the plugin runtime must provide a multi-threaded runtime or preemption silently stops working. `tests/misbehaving_plugin.rs` is the only place this is enforced, via `#[tokio::test(flavor = "multi_thread")]` on the runaway cases; it was found by writing those tests, not by design.

A related consequence: a plugin that exceeds its deadline is reported as `FailureKind::Deadline`, distinct from `FailureKind::Trapped` for a guest fault. wasmtime does not document which trap an exceeded epoch deadline raises, so that mapping rests on the preemption test rather than on the engine's contract.

---

## 10. Grant UX flow

Three touchpoints. No fourth — adding more clicks erodes trust.

### Install screen
- Shows: plugin name, publisher (signed badge or "unsigned" red banner), required capabilities grouped by impact, optional capabilities (collapsed by default).
- Format: `[ICON] Read your database schemas` + purpose string from manifest.
- Single Install / Cancel. No granular toggles at install — required is all-or-nothing.

### First-use prompt (optional capabilities only)
- Triggered when plugin first calls a method requiring optional capability.
- Three buttons: **Allow once** / **Allow always** / **Deny**.
- Rationale text = manifest purpose string. Absent → the capability is shown without one.
- Cooldown: a denied capability stays denied until user visits Permissions panel. No re-prompt spam.

### Permissions panel
- Lists every installed plugin × capability matrix.
- Toggle revokes capability instantly (next plugin call fails).
- "Re-enable" for plugins disabled by crash budget.
- Shows last-N crashes per plugin (auditable).
- Per-plugin "Uninstall" button.

**No global toggle** ever. Obsidian's `Restricted Mode` taught us this collapses to TOFU.

---

## 11. Storage isolation

| Storage | Desktop | Web | Capability |
|---|---|---|---|
| Plugin code (read-only) | `~/.plamenix/plugins/<id>/` | `/var/lib/plamenix/plugins/<id>/` | implicit (host-managed) |
| Plugin data (R/W) | `~/.plamenix/plugins/<id>/data/` | `/var/lib/plamenix/plugins/<id>/data/` | `fs.read.dir.plugin-data`, `fs.write.dir.plugin-data` (default-granted) |
| Plugin settings | `~/.plamenix/plugins/<id>/settings.toml` | server SQLite per-plugin row | `settings.read`, `settings.write` (own scope only, default-granted) |
| Secrets | OS keychain `dev.plamenix.plugins.<id>` | server keychain (e.g. Vault, env-injected) | `secrets:read`, `secrets:write` (per service key) |
| Workspace files | project root | server-side configured | `fs.read.dir.workspace`, `fs.write.dir.workspace` (optional, install-prompted) |

**Cross-plugin isolation enforced structurally**: WASI preopens hand the plugin a single `fs.directory` resource scoped to its own data dir. Plugin cannot enumerate or reach other plugin dirs. WASI does the path validation (no `..`, no abs paths, no out-of-tree symlinks).

**No shared writable state** — VSCode's `state.vscdb` cross-extension leak is refused by design. Inter-plugin communication only via the host-mediated event bus with namespaced channels.

---

## 12. Crash isolation + supervisor

Per OTP, with Rust+wasmtime mapping:

| OTP concept | wasmtime equivalent |
|---|---|
| Process heap | `Store<PluginCtx>` |
| Process isolation | One Store per plugin instance |
| Exit signal | `wasmtime::Trap` |
| Kill-on-timeout | `Engine::increment_epoch()` + per-store deadline |
| Memory cap | `ResourceLimiter` wired via `Store::limiter` |
| Supervision tree | Tokio task hierarchy; parent owns child Store handles |
| Restart strategy | Custom supervisor module; matches on trap variant |
| Restart intensity | Token-bucket per plugin |

### Supervisor module

Lives in `plamenix-plugin-host/src/supervisor.rs` (new). Responsibilities:
- Owns the `JoinHandle` for every active plugin Store
- On `Trap`: classify (OOM / fuel / epoch / divide-by-zero / host-import-error / unreachable)
- Consult `restart_policy`:
  - `permanent` → restart unless budget exhausted
  - `transient` → restart only if Trap was abnormal (not graceful `Activation::Failed`)
  - `temporary` → never restart
- Bound restart attempts: token bucket per plugin, default 3 in 60s. Exceeded → `DISABLED`, notification + Permissions panel entry.
- Drop the Store on permanent failure (the only way to reclaim crashed plugin memory).

**Host-side panic discipline**: every host import wrapped in `catch_unwind`-equivalent. A panic inside a host function called from wasm corrupts the embedder process — the one place Rust+wasmtime is weaker than OTP. Lint rule (clippy) refuses `unwrap`/`expect` in `host_impl.rs` modules.

---

## 13. Trust model

Plamenix installs plugins from exactly two places. There is no
marketplace, no registry, and no installing from a URL.

| Distribution path | Signing | UX |
|---|---|---|
| Built-in | Implicit — compiled into the host binary | No badge; treated as core |
| Sideload from a local `.plx` file | Optional, integrity only | Capability list, plus the signing key when one is present |

**Why so narrow.** A curated marketplace is the only thing that can turn
a signature into a statement about *who* wrote a plugin. Without one, a
signature proves the archive was not altered after it was signed and
nothing more — the key travels inside the bundle, so anyone can produce
a validly signed plugin. Shipping a "verified" badge on that basis would
tell the user something the system cannot know.

So the trust decision lives where the user can actually make it: the
file picker. They chose the file; the host sandboxes it regardless. This
is how VS Code `.vsix`, JetBrains local plugin installs and unsigned
Firefox XPIs all work before an ecosystem exists.

Installing from a URL was removed rather than left disabled. It is the
one path where the user does *not* see what they are getting before it
arrives, and it needs exactly the curation that does not exist. Fetching
a plugin is therefore the user's job, using a browser, where the usual
signals — the domain, the TLS padlock, the project's own site — are
visible and familiar.

**What signing does mean.** A `.plx` may carry `signature.bin` covering
its other contents. Verification answers one question — *do these bytes
match this key?* — and the API says so: the outcome distinguishes an
intact archive from a tampered one, and never claims the publisher is
who they say they are. The signing key is surfaced to the user, not
interpreted for them.

**No remote code loading**: like MV3. The `.plx`'s wasm + ui.mjs are the
only executable surface. A plugin fetching JS at runtime → host refuses
to evaluate (`script-src 'self'` CSP).

**Update consent**: if a plugin update adds a *new required* capability,
the user must re-consent. Optional capabilities reset to "not granted"
on a major-version bump.

**What a registry would change, if one is ever built.** Re-signing by a
curator is what makes a badge meaningful, so trust roots, pinning and
publisher identity belong to that work — not to this beta. Nothing here
forecloses it: the signature format already covers whole-archive
integrity, which is what a curator would counter-sign.

---

## 14. Edition portability — the tri-state model

The user's key differentiator. Plugins declare `targets = ["desktop", "web"]` or subset. Host filters at install/load.

### Per-edition capability matrix

| Capability | Desktop | Web | Universal? |
|---|---|---|---|
| `db:*` | ✓ | ✓ | U |
| `db.write:*` | ✓ | ✓ | U |
| `db.session:context.read` | ✓ | ✓ | U |
| `fs:plugin-data` | ✓ (`~/.plamenix/...`) | ✓ (`/var/lib/plamenix/...`) | U (semantic same, path differs) |
| `fs:workspace` | ✓ (user's project) | ✓ (server-configured) | U |
| `net.https.<host>` | ✓ | ✓ | U |
| `secrets:*` | ✓ (OS keyring) | ✗ (no equivalent in M1 web) | D-only |
| `notify:display` | ✓ (OS notification) | △ (in-browser toast, different shape) | D-preferred |
| `clipboard:*` | ✓ (system) | ✓ (`navigator.clipboard`) | U |
| `event:*` | ✓ | ✓ | U |
| `settings:*` | ✓ | ✓ | U |
| `theme:register` | ✓ | ✓ | U |
| `command:*` | ✓ | ✓ | U |
| Subprocess escape hatch | ✓ (native binary) | ✗ | D-only |

### Author guidance

| Plugin pattern | `targets` |
|---|---|
| Pure WASM + UI using `db:*`, `http:*`, `event:*`, `settings:*` only | `["desktop", "web"]` (DEFAULT) |
| Needs OS keyring, clipboard sync, native subprocess | `["desktop"]` |
| Needs server-side multi-tenant logic, REST endpoints, scheduled jobs (future capabilities) | `["web"]` |

### Enforcement

- **At manifest validation**: `plamenix-cli validate` warns if declared capabilities don't match `targets` (e.g. requesting `secrets:*` but `targets = ["web"]`).
- **At install**: host refuses if plugin's `targets` doesn't include current edition. Clear error: "This plugin is desktop-only and cannot be installed on Plamenix Web."
- **At runtime**: capability call gated by both grant set AND edition compatibility. Defense in depth.

### Universal default = right incentive

Plugin authors write once, target both editions by default. Per-edition plugins exist when they genuinely need edition-specific capabilities. The host enforces the line.

---

## 15. Anti-patterns refused

1. **Obsidian's TOFU global toggle** — POLA demands granularity. Refused.
2. **VSCode's shared `state.vscdb`** — never give plugins shared writable state. Per-plugin storage only.
3. **VSCode's process-isolation-as-security** — separate Node process with full user authority is not sandboxed. WASM Component Model is the actual boundary.
4. **MV3's `<all_urls>`** — refuse manifests with unbounded `net.https` scope.
5. **Install-time-only consent** — users learn to click through. Required = install-time, optional = first-use.
6. **Remote code loading** — only signed `.plx` contents execute. No URL-loaded JS.
7. **Ambient host imports** — every host function in plugin world is capability-checked. No "open this file" general API.
8. **DOM passthrough** — plugins never get raw React refs. UI extension is typed slots only.
9. **Sync plugin code on hot paths** — all plugin calls are async-shaped. Even when WASM is in-process.
10. **Plugin discovery requiring plugin code** — manifest alone must be enough to render menus / palette entries.
11. **Eager activation as default** — every plugin lazy-activates on its declared triggers.
12. **`process` capability ever** — no shell-out escape hatch. First-party companion binaries handle this with narrow host-mediated interfaces.
13. **Re-prompt on update** — a new required capability needs fresh consent, however the plugin was installed.
14. **Constructor side-effects in plugin classes** — IntelliJ rule. Plugin construction is cheap and deterministic. Work in `activate()`.
15. **Single namespace for first-party + third-party contributions** — IntelliJ separates `com.intellij.*` from plugin-defined. Plamenix uses `plamenix:*` vs `<plugin-id>:*`.

---

## 16. Implementation sections — M1 plugin completion

**Scope decision (2026-05-27)**: full plugin suite — host + SDK + tooling + all contribution points + dynamic surface + supervisor + UX + bundled first-party plugins — ships in M1 by 2026-06-15. No deferral to 1.x.

Tracker: `PLUGIN_TRACKER.md` (sibling to this doc). Sections I0–I9 below, with parallelism noted.

### I0 — Foundation (days 1–3, blocks all)

- WIT contract additions: all 4 worlds (`plugin-minimal` / `plugin-db-reader` / `plugin-db-writer` / `plugin-integrated`) + orthogonal capabilities
- Capability grammar TOML schema (manifest validator)
- Event catalog + interceptor catalog formalized
- Update `plamenix/MILESTONES.md` M1 section
- This document adopted as `plamenix/docs/plugin-architecture.md` (or kept as workspace-level reference)

### I1 — Web plugin host (days 4–10, parallel with I2 + I3)

- New `plamenix-plugin-host-node` napi crate, wraps `plamenix-plugin-host` core
- Wire into Fastify: `loadPlugin / activate / invoke / deactivate`
- Multi-tenant lifecycle: shared instance, per-session context
- Plugin storage: `/var/lib/plamenix/plugins/<id>/`

### I2 — React SDK (days 4–10, parallel)

- `@plamenix/plugin-react` npm package
- `<PluginOutlet point="..." />` slot component
- `usePluginAPI<T>()` hook
- ESM dynamic loader (works in Tauri webview + browser)
- Hot-load + unload

### I3 — Contribution registry (days 4–8, parallel)

- Registry singleton + manifest→registry on activate
- Built-in features re-register via same API (internal-server pattern, VSCode model)
- Wire first 3 consumers: `cell_renderers`, `export_formats`, `commands` (`sidebar_panels` already there)

### I4 — Built-in extractions (days 7–12, depends on I3)

- Extract BlobViewer → `@plamenix/plugin-blob-renderer`
- Extract 5 export formats → `@plamenix/plugin-{csv,json,sql,xml,xlsx}-export`
- Extract 32 tips → `@plamenix/plugin-tips-firebird`
- Extract `RECREATE TABLE` + `SET STATISTICS INDEX` → `@plamenix/plugin-dba-toolbox`
- Add `@plamenix/plugin-json-cell-renderer` (new, tri-state validator, `targets=["desktop","web"]`)
- 9 first-party `.plx` plugins total. Each ~½–1 day, parallelizable.

### I5 — Remaining contribution points (days 8–14, parallel after I3 pattern is set)

14 points wired via registry pattern:
- `keybindings` · `menus` · `toolbar_buttons` · `object_inspectors` · `schema_actions`
- `sql_formatters` · `auth_providers` · `themes` · `settings_panels` · `dashboard_sections`
- `status_bar_items` · `completion_providers` · `diagnostics_providers` · `import_sources`

### I6 — Dynamic surface (days 10–15, depends on I0)

- Event bus: WIT + topic registry + emit/subscribe + auto-cleanup on deactivate
- ~30 events emitted from shell hook points (per §7 catalog)
- 8 interceptor chains: priority + Cancel/Replace + 500ms budget (per §8 catalog)
- Built-in interceptors (destructive-DROP confirmation, etc.)

### I7 — UX + tooling (days 12–17)

- Install dialog (required batch + optional collapsed)
- First-use prompt (Allow once / Allow always / Deny)
- Permissions panel (revoke + crash budget display + re-enable)
- Install/uninstall flows: desktop file picker + URL fetch + web admin endpoint
- `.plx` packaging spec + `plamenix-cli` (new/build/pack/install/validate)
- Signature format + verifier

### I8 — Supervisor + crash handling (days 14–18)

- Supervisor module in `plamenix-plugin-host/src/supervisor.rs`
- Store-per-plugin enforcement
- Restart policy from manifest (permanent/transient/temporary)
- Crash budget 3/60s → `DISABLED` state
- `DISABLED` UI surface in Permissions panel

### I9 — Tests + docs + release (days 16–20)

- E2E test harness for plugin loading + activation
- Per-edition smoke tests
- Capability enforcement tests
- Crash isolation tests
- Plugin author tutorial + API reference (SDK + plugin-react) + capability model deep-dive + edition targeting guide
- Smoke test all 9 bundled plugins on both editions
- Update `docs/plugin-system.md` to reflect shipped reality
- Tag `1.0.0-beta`

### Calendar

```
Day  | Date          | Sections
-----|---------------|--------------------------------
1-3  | 05-27 → 05-29 | I0
4-10 | 05-30 → 06-05 | I1 + I2 + I3 (parallel)
7-12 | 06-02 → 06-07 | I4 (overlaps I3 tail)
8-14 | 06-03 → 06-09 | I5
10-15| 06-05 → 06-10 | I6
12-17| 06-07 → 06-12 | I7
14-18| 06-09 → 06-13 | I8
16-20| 06-11 → 06-15 | I9
```

### Risk

Tight. Three load-bearing items (I1 web host, I2 React SDK, I6 dynamic surface) each have unknowns that could blow the budget. If any slips by 3+ days, M1 date moves.

### Deferred beyond M1 (explicitly NOT in scope, kept for 1.x roadmap)

- Automated capability audit for bundles the user is about to install
- Reproducible builds enforcement
- Community SDKs (Go, TypeScript) — per ADR 0010, Rust-only for 1.0.x
- Multi-tenant per-tenant plugin storage on web (single-machine M1 assumption)

---

## 17. Decisions to confirm before implementation

1. **Single host crate vs split per edition?** Recommend: `plamenix-plugin-host` (Rust core, shared) + `plamenix-plugin-host-node` (napi wrapper). Desktop links the core directly; web links via napi.
2. **WIT world granularity** — 4 tiers (above) or finer-grained? Recommend 4; more is over-engineered for 1.0.x.
3. **Signing format** — *deferred 2026-08-07*: dual author/publisher signing only becomes meaningful with a curator to be the second signer. Until then a single author signature covering the archive is all that can be verified. Revisit alongside any registry work.
4. **Reproducible builds** — *deferred 2026-08-07*: an audit pathway worth having, but it needs a published source-to-artefact mapping to check against. Revisit alongside any registry work.
5. **Plugin storage scoping on web** — per-tenant or shared? Recommend shared in M1 single-machine assumption; per-tenant becomes a 1.x feature when multi-tenant lands.
6. **Theme contribution** — runtime API or pure-static? Recommend pure-static (CSS variables in manifest). No plugin code runs to apply a theme.
7. **`subprocess` capability** — *resolved 2026-08-07*: removed entirely. First-party companion binaries are a separate distribution channel.

---

## 18. What's deliberately NOT in this design

- **Multi-language SDKs** (Go, TypeScript) — per ADR 0010, Rust only for 1.0.x.
- **Marketplace and registry** — not built, and not planned for 1.0.0-beta. Local `.plx` sideload only; URL install was removed on 2026-08-07 (see §13).
- **Plugin chat / agent integration (MCP)** — defer to 1.x; align with whatever MCP-style emerges.
- **Visual plugin builder** — never (per Atom failure mode lessons).
- **Hot-swap of host SPI** — host SPI changes are SemVer-major; old plugins are refused, not patched.
- **Plugin-to-plugin direct calls** — go through the event bus or shared commands, never direct binding.
- **Background services / long-running plugin daemons** — plugins activate on triggers, do work, return. No persistent plugin processes (web edition multi-tenancy makes this hard; defer to 1.x).

---

## 19. Resolved decisions (2026-05-27 sign-off)

1. **Adopt as canonical plugin architecture** for M1. Workspace copy at `PLUGIN_ARCHITECTURE.md`; may also be mirrored into `plamenix/docs/plugin-architecture.md` during I0.
2. **Full plugin suite ships in M1** by 2026-06-15. No deferral. Sections I0–I9 in §16 are the plan.
3. **`docs/plugin-system.md` not trimmed** — kept as-is; I9 updates it to match shipped reality once everything lands.
4. **"No `process` capability ever"** confirmed. First-party companion binaries handle anything that needs shell-out, via narrow host-mediated interfaces.
5. **Capability grammar (§5 table)** confirmed canonical for 1.0.x.

---

## Sources

**Modern IDEs**: VS Code API ([reference](https://code.visualstudio.com/api/references/vscode-api), [contribution points](https://code.visualstudio.com/api/references/contribution-points), [activation events](https://code.visualstudio.com/api/references/activation-events)) · JetBrains Platform SDK ([welcome](https://plugins.jetbrains.com/docs/intellij/welcome.html), [extensions](https://plugins.jetbrains.com/docs/intellij/plugin-extensions.html), [services](https://plugins.jetbrains.com/docs/intellij/plugin-services.html)) · Theia ([extensions](https://theia-ide.org/docs/extensions/), [services + contributions](https://theia-ide.org/docs/services_and_contributions/)) · Zed ([docs](https://github.com/zed-industries/zed/tree/main/docs/src/extensions)) · Atom retrospectives ([gHacks](https://www.ghacks.net/2022/06/09/githubs-atom-text-editor-will-be-retired-in-december/), [Grokipedia](https://grokipedia.com/page/Atom_(text_editor))) · Obsidian ([plugin docs](https://docs.obsidian.md/Plugins/Getting+started/Build+a+plugin), [events](https://docs.obsidian.md/Plugins/Events), [security critique](https://biggo.com/news/202509200713_Obsidian_Plugin_Security_Concerns))

**Foundational patterns**: Microkernel (POSA, [Wikipedia](https://en.wikipedia.org/wiki/Microkernel), [Richards OSBA](https://www.oreilly.com/library/view/software-architecture-patterns/9781098134280/ch04.html)) · OSGi ([architecture](https://www.osgi.org/resources/architecture/), [bundle lifecycle](https://docs.osgi.org/javadoc/r4v401/org/osgi/framework/Bundle.html)) · Erlang/OTP ([supervisor design](https://www.erlang.org/doc/design_principles/sup_princ.html)) · Hexagonal ([Cockburn](https://alistair.cockburn.us/hexagonal-architecture)) · Event-driven ([Fowler](https://martinfowler.com/articles/201701-event-driven.html), [Event Sourcing](https://martinfowler.com/eaaDev/EventSourcing.html)) · Plugin pattern ([Fowler](https://martinfowler.com/eaaCatalog/plugin.html)) · Interceptor pattern ([Wikipedia](https://en.wikipedia.org/wiki/Interceptor_pattern)) · Domain vs integration events ([de la Torre](https://devblogs.microsoft.com/cesardelatorre/domain-events-vs-integration-events-in-domain-driven-design-and-microservices-architectures/))

**Sandboxing + security**: WASM Component Model ([spec](https://component-model.bytecodealliance.org/), [WIT design](https://component-model.bytecodealliance.org/design/wit.html)) · WASI Preview 2 ([Capabilities and Filesystems](https://blog.sunfishcode.online/capabilities-and-filesystems/)) · Manifest V3 ([Chrome](https://developer.chrome.com/docs/extensions/reference/manifest)) · Object Capability Model ([Wikipedia](https://en.wikipedia.org/wiki/Object-capability_model), [awesome-ocap](https://github.com/dckc/awesome-ocap)) · POLA ([Wikipedia](https://en.wikipedia.org/wiki/Principle_of_least_privilege)) · wasmtime ([Config](https://docs.wasmtime.dev/api/wasmtime/struct.Config.html), [ResourceLimiter](https://docs.wasmtime.dev/api/wasmtime/trait.ResourceLimiter.html), [security](https://docs.wasmtime.dev/security.html), [April 2026 advisories](https://bytecodealliance.org/articles/wasmtime-security-advisories)) · Deno permissions ([docs](https://docs.deno.com/runtime/fundamentals/security/)) · VSCode extension security ([runtime security](https://code.visualstudio.com/docs/configure/extensions/extension-runtime-security))
