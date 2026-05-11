# Architecture

Plamenix is a Firebird database IDE delivered as two editions sharing a
single React UI:

- **Desktop edition** — Tauri 2 shell + Rust backend (`rsfbclient` native
  bindings, wasmtime plugin host).
- **Web edition** — Fastify (Node) server + same React UI, with NAPI
  bindings exposing `rsfbclient` to Node.

## Polyrepo

Five git repositories live as sibling directories inside one parent
workspace:

```
<parent-dir>/
├── plamenix/              ← meta-workspace (this repo): docs, milestones, justfile
├── plamenix-core/         ← shared Rust crates (types, db driver, plugin host, SDK)
├── plamenix-ui/           ← shared React library (components, hooks, stores, transport)
├── plamenix-desktop/      ← Tauri 2 desktop edition
└── plamenix-web/          ← Fastify + React web edition
```

Each repo has its own `git`, its own `CLAUDE.md`, its own build. They
coordinate via published artifacts (crates.io for Rust, npm for
TypeScript) plus local Cargo `[patch]` / `pnpm link` overrides for
cross-repo development.

No git submodules. They are abandoned as an anti-pattern for modern OSS
polyrepos. See [adr/0007-polyrepo-no-submodules.md](./adr/0007-polyrepo-no-submodules.md).

## Layered split inside `plamenix-core`

Pragmatic, **not** strict hexagonal. Traits exist only at three proven
swap-points; everything else is concrete:

| Swap-point | Trait | Reason |
|------------|-------|--------|
| Database driver | `DbDriver` | rsfbclient today, alternative drivers possible, plugin-supplied drivers later. |
| Plugin host | `PluginHost` | wasmtime today, isolation discipline. |
| Secret store | `SecretStore` | in-memory + OS keyring. |

Internal feature crates (`plamenix-db`, `plamenix-schema`, `plamenix-export`,
`plamenix-plugin-host`, `plamenix-config`, `plamenix-secret`,
`plamenix-plugin-sdk`) are flat modules and concrete functions inside.

See [principles.md](./principles.md) for the CUPID / AHA reasoning that
motivates this layout.

## Editions share the React UI

`@plamenix/ui` (in `plamenix-ui/`) is a transport-agnostic React library.
It imports neither `@tauri-apps/*` nor `fetch`. Every host interaction
passes through a `Transport` interface implemented by the consuming
edition:

```
React components / hooks / stores
            │
            ▼
       Transport  ◄── injected by edition at boot
            │
    ┌───────┴────────┐
    ▼                ▼
Tauri invoke    HTTP fetch
(plamenix-      (plamenix-
 desktop)        web)
```

See [transport.md](./transport.md) for shape and lifecycle.

## Plugin extensibility

Microkernel + plugin model. Core stays core; plugins augment via
contribution points. Plugins ship in two halves:

- **Rust half** — compiled to WASM Component Model (`wasm32-wasip2`),
  loaded by `wasmtime` in the host, sandboxed, capability-gated.
- **React half** — ESM bundle imported dynamically by the host into the
  plugin slot registry.

Both halves ship in a single `.plx` bundle alongside a `manifest.toml`.

See [plugin-system.md](./plugin-system.md), [contribution-points.md](./contribution-points.md),
[plugin-manifest.md](./plugin-manifest.md), [capability-model.md](./capability-model.md).

## State model

Per-tab isolation enforced by typed identifiers (`TabId`). Per-tab Rust
state lives in `tauri::State<TabRegistry>` (desktop) or per-session
server state (web). Per-tab React state lives in tab-scoped Zustand
stores; global state lives in singleton stores.

See [state-model.md](./state-model.md).

## Splash, boot, restore

Desktop opens a JetBrains-style splash window while plugins are scanned
and the host is initialised, then transitions to the main window once
ready. Web edition shows an inline loading state instead (no separate
window possible in a browser).

See [splash-window.md](./splash-window.md).

## Firebird

`rsfbclient` is the canonical driver in both editions. Native fbclient
is bundled per platform and loaded via `with_dyn_load(<path>)`, giving
Plamenix access to MON$ tables, BLOB streaming, ARRAY columns,
DECFLOAT, time-zone types, and the encryption callback interface that
pure-Rust mode does not currently support. Pure-Rust mode is retained
as a fallback for environments where the native library is unavailable.

See [firebird-driver.md](./firebird-driver.md), [encryption.md](./encryption.md),
[napi-rsfbclient.md](./napi-rsfbclient.md).
