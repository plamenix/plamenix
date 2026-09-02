# Plugin system

Plamenix supports third-party plugins as a first-class concern from
`1.0.0-beta`. A plugin extends both the Rust backend and the React UI
from one bundle.

This doc is the **how it ships** overview. The **why** lives in
[plugin-architecture.md](./plugin-architecture.md); the hands-on
walkthrough lives in [tutorial-first-plugin.md](./tutorial-first-plugin.md).

## What ships in M1

| Layer | Status |
|---|---|
| Rust host (`plamenix-plugin-host` crate) | Shipped. Both editions embed it (desktop directly, web via the `@plamenix/plugin-host-node` napi binding). |
| Plugin SDK (`plamenix-plugin-sdk` crate) | Shipped in-workspace + rustdoc + README + `docs.rs` metadata. `publish = false` today; cargo publish runs as part of tagging `1.0.0-beta`. |
| React SDK (`@plamenix/ui/plugin-react` subpath) | Shipped. Subpath export of the `@plamenix/ui` package; no separate npm package. README at `plamenix-ui/src/plugin-react/README.md`. |
| `.plx` archive format | Shipped — PKZIP-with-deflate. Reader/writer in `plamenix-plugin-host`. |
| `plamenix-cli` (`new` / `build` / `pack` / `validate` / `keygen` / `sign` / `install`) | Shipped. `install` is a structured stub on M1 (returns `NotYetImplemented` until the HTTP client lands in M2); every other subcommand is live. |
| Ed25519 signing + verifier | Shipped (I7.15 + I7.16). Signature banner on the install dialog reflects `verified` / `unsigned` / `invalid` per [capability-model.md](./capability-model.md). |
| Supervisor + crash budget + epoch interruption + resource limits | Shipped (I8.1-I8.9). |
| Nine first-party bundled plugins | Shipped (I4.1-I4.9). Cross-cutting registrar smoke at `plamenix-ui/src/db/builtins/bundled-plugins-smoke.test.tsx`; manual screenshot checklist at [bundled-plugins-smoke-checklist.md](./bundled-plugins-smoke-checklist.md). |
| Multi-language plugin SDKs (Go / TS / Python) | **Not in M1.** Rust-only per ADR 0010. |
| Marketplace / registry | **Not built, not planned for 1.0.0-beta.** Local `.plx` sideload via the file picker is the only install path; URL install was removed on 2026-08-07. See the trust model in [plugin-architecture.md](./plugin-architecture.md). |

## Two layers, one bundle

Every plugin has at most two halves:

- **Rust half** — compiled to **WebAssembly Component Model**
  (`wasm32-wasip2`) and loaded into the host by `wasmtime`. Sandboxed.
  Capability-gated. ABI stable across host versions.
- **React half** — an ESM bundle (`ui.mjs`) dynamic-imported into the
  shell's contribution registry. Renders into the slots declared in the
  manifest.

Plugins that only contribute UI (e.g. the JSON cell renderer at
`plamenix-core/crates/plamenix-plugin-host/examples/json-cell-renderer/`)
ship only `ui.mjs` + `manifest.toml`; the activator skips wasmtime
instantiation entirely. Plugins that only need backend logic ship only
`plugin.wasm`.

The halves ship in one `.plx` archive together with a `manifest.toml`
describing metadata, requested capabilities, contribution points,
edition `targets`, restart policy, and event subscriptions.

## Why WASM (and not native dylib, subprocess, or scripting)

| Strategy | Verdict |
|----------|---------|
| **WASM (wasmtime + WIT)** | **Chosen.** One artifact across OS/arch, sandbox boundary, ABI stable forever, ~80–95% of native speed for DB IDE workloads. |
| Native dylib (`abi_stable`) | Rejected. Author ships 6+ binaries, ABI breaks each rustc release, no sandbox — the DBeaver / OSGi pain Plamenix avoids. |
| Subprocess + JSON-RPC | Kept as escape hatch for plugins that need raw OS access (Windows Credential Manager, macOS Keychain). Manifest flag `requires_subprocess = true` paired with the `runtime.subprocess` capability. |
| Compile-time feature flags | Not third-party friendly. Skipped. |
| Embedded scripting (mlua / rhai) | User-script territory, not extension territory. Not for Plamenix. |

See [adr/0003-wasm-component-model-plugins.md](./adr/0003-wasm-component-model-plugins.md).

## Toolchain

- **Runtime**: `wasmtime` (Component Model 1.0, WASI Preview 2).
- **Contract**: WIT files, bindings via `wit-bindgen` for Rust.
  TypeScript bindings aren't auto-generated yet — the React SDK ships a
  hand-written `PluginAPI` interface against the same WIT shape.
- **Rust SDK**: `plamenix-plugin-sdk`. Thin macros over `wit-bindgen`
  plus subprocess-protocol helpers. README at
  `plamenix-core/crates/plamenix-plugin-sdk/README.md`. `cargo publish`
  runs at tag time; in-workspace consumers (`hello-plugin` example,
  scaffold output) link by path until then.
- **React SDK**: `@plamenix/ui/plugin-react` subpath. Exposes
  `<PluginOutlet point="..."/>`, `<PluginAPIProvider>`, the
  `usePluginAPI()` hook, the registry primitives, and the
  contribution-loader helpers. Reference at
  `plamenix-ui/src/plugin-react/README.md`.
- **CLI**: `plamenix-cli new | build | pack | validate | keygen | sign | install`.
  Per the I7 subcommands.

## Plugin author language

**Rust only for v1.0.x.** WIT is language-agnostic; future SDKs in Go /
JS / Python are technically possible via the Component Model, but
official support is Rust only at `1.0.0`. Additional SDKs land when
community demand arises and core-team expertise covers them.

The UI half is always TypeScript / React because that's how browsers
work. Plugins are therefore bi-lingual (Rust + TS) by design, but Rust
is the only "extension language" decision.

## Bundle layout

`plamenix-cli new <id>` scaffolds a flat layout (both halves share the
top-level `src/`):

```
my-plugin/
├── manifest.toml         # metadata, capabilities, contributions, targets
├── Cargo.toml            # depends on plamenix-plugin-sdk
├── package.json          # depends on @plamenix/ui (for ./plugin-react)
├── src/
│   ├── lib.rs            # Rust plugin entry — #[plugin_export] fns
│   └── ui.tsx            # React UI module — sidebar panel stub
└── README.md
```

`plamenix-cli build` compiles `src/lib.rs` to `wasm32-wasip2` via cargo
and `src/ui.tsx` to ESM via vite (with `react` / `react-dom` / `lucide-react`
externalised per [plugin-authoring.md](./plugin-authoring.md)).
`plamenix-cli pack` zips the build output into a `.plx` with this
layout:

```
my-plugin-<version>.plx   # PKZIP-with-deflate
├── manifest.toml         # required, top-level
├── plugin.wasm           # optional — WASM half
├── ui.mjs                # optional — React UI module
└── resources/            # optional — static assets the UI references
    └── ...
```

Path-traversal guard refuses entries with `..`, NUL bytes, or absolute
paths at extract time. Subprocess plugins ship their native binary
inside the archive's `bin/<os>/<arch>/` directory; see
[edition-targeting.md](./edition-targeting.md) for the per-OS bundling
convention.

Signed bundles ship a sibling `signature.json` outside the archive;
`plamenix-cli sign` produces it from an Ed25519 private key.

## Loading flow

1. **Discover.** The host scans plugin directories — `~/.plamenix/plugins/`
   on desktop (Tauri-managed); `PLUGINS_PATH` env var (default
   `./plugins`) on web. Each subdirectory containing `manifest.toml`
   is a candidate.
2. **Parse + edition filter.** `Manifest::parse` validates the grammar
   for capabilities, runs the `requires_subprocess` / `runtime.subprocess`
   pairing check, and gates on the `targets` list against the running
   edition. Manifests targeting only `desktop` are skipped (with a
   recorded failure) on the web edition; ditto vice versa. See
   [edition-targeting.md](./edition-targeting.md).
3. **Stage.** The wasm component, if present, is parsed by wasmtime up
   front to surface compile errors before activation. UI-only bundles
   skip this step.
4. **Register UI contributions.** The shell registers the manifest's
   declared contribution points (`sidebar_panels`, `cell_renderers`,
   `commands`, etc.) so they surface in the React tree the moment the
   relevant view mounts. The `ui.mjs` module is dynamic-imported when
   the UI shell first needs it.
5. **Activate.** Both editions activate every staged plugin at
   bootstrap (web: `bootstrapPlugins` calls `activatePlugin` per
   bundle; desktop: the Tauri command bridge does the same on app
   start). Activation runs `activate()` inside a per-plugin wasmtime
   store with the granted capabilities linked. The supervisor records
   the lifecycle state (`Active` / `Stopped` / `Disabled`).
6. **Gate runtime calls.** Each host function exposed via WIT performs
   a capability check before doing the work. Denied calls surface as
   `PluginError::PermissionDenied` to the plugin, which handles them
   gracefully — the host never crashes from a permission failure.
7. **Isolate failures.** A trapping plugin returns a clean error to the
   caller; the supervisor restarts per the manifest's `restart_policy`
   (`permanent` / `transient` / `temporary`). A plugin that exceeds the
   crash budget (default 3 restarts in 60s) lands in `Disabled` and
   surfaces in the Permissions panel for the user to re-enable.

The install / first-use flow is one layer up: when the user picks a new
`.plx`, the install dialog (I7.1) shows required permissions as a
batch + optional ones behind a disclosure. The first-use prompt (I7.2)
asks `Allow once / Allow always / Deny` when a plugin tries to use an
optional permission the user skipped at install time. The Permissions
panel (I7.3 / I7.4) is the audit + revoke surface. See
[capability-model.md](./capability-model.md).

## Dynamic surface

The static contribution registry is one half of the extension surface;
the other half is the **dynamic** one — runtime register/listen/emit
calls plugin code makes after activation. Two primitives:

- **Event bus** (`*ed` topics, past-tense, fire-and-forget). See
  [plugin-events.md](./plugin-events.md).
- **Interceptor chains** (`*ing` topics, present-participle, may
  mutate or cancel). 500ms budget per chain, priority-ordered
  handlers, fail-open on trap. See
  [plugin-interceptors.md](./plugin-interceptors.md).

Both follow the discipline laid out in `plugin-architecture.md` §7-§8.

## Versioning policy

- **Plugin host** version follows Plamenix's SemVer line.
- **`plugin_api` WIT interface** is independently versioned. Breaking
  changes mint a new interface version (`plugin-api@1.0`,
  `plugin-api@2.0`); the host binds multiple versions simultaneously so
  old plugins keep working.
- Deprecated functions are marked `#[deprecated]` in the SDK and kept
  for at least three minor releases before removal.
- Capability additions are backward-compatible — old plugins that don't
  request a new capability are unaffected.
- Narrowing a plugin's own `targets` field is a **major-version**
  change per [edition-targeting.md](./edition-targeting.md) — users on
  the now-excluded edition lose the plugin.

## See also

- [plugin-architecture.md](./plugin-architecture.md) — design spec
  (microkernel, ports, capability tiers, supervisor, trust model).
- [tutorial-first-plugin.md](./tutorial-first-plugin.md) — hands-on
  walkthrough: scaffold → build → sign → install.
- [plugin-authoring.md](./plugin-authoring.md) — externals, manifest,
  dev loop, verification.
- [plugin-manifest.md](./plugin-manifest.md) — `manifest.toml` schema.
- [plugin-events.md](./plugin-events.md) — event-bus topics.
- [plugin-interceptors.md](./plugin-interceptors.md) — interceptor
  chains.
- [contribution-points.md](./contribution-points.md) — every static
  slot.
- [capability-model.md](./capability-model.md) — permission grammar,
  install-time consent, signature trust tiers.
- [edition-targeting.md](./edition-targeting.md) — `targets`
  decision tree, enforcement, migration.
- [bundled-plugins-smoke-checklist.md](./bundled-plugins-smoke-checklist.md) —
  pre-tag manual walkthrough for the nine first-party plugins.
