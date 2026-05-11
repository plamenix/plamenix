# Plugin system

Plamenix supports third-party plugins as a first-class concern from
`1.0.0-beta`. Plugins extend both the Rust backend and the React UI from
a single bundle.

## Two layers, one bundle

Every plugin has at most two halves:

- **Rust half** — compiled to **WebAssembly Component Model**
  (`wasm32-wasip2`) and loaded into the host by `wasmtime`. Sandboxed.
  Capability-gated. ABI stable across host versions.
- **React half** — an ESM bundle imported dynamically by the host into
  the plugin slot registry. Renders into the contribution points
  declared in the manifest.

The two halves ship in a single `.plx` archive together with a
`manifest.toml` describing metadata, requested capabilities, and the
contribution points filled.

## Why WASM (and not native dylib, subprocess, or scripting)

| Strategy | Verdict |
|----------|---------|
| **WASM (wasmtime + WIT)** | **Chosen.** One artifact across OS/arch, sandbox boundary, ABI stable forever, ~80–95 % of native speed for DB IDE workloads. |
| Native dylib (`abi_stable`) | Rejected. Author ships 6+ binaries, ABI breaks each rustc release, no sandbox — DBeaver / OSGi pain we are explicitly avoiding. |
| Subprocess + JSON-RPC | Kept as escape hatch for plugins that need raw OS access (Windows Credential Manager, macOS Keychain). Manifest flag `requires_subprocess = true`. |
| Compile-time feature flags | Not third-party friendly. Skipped. |
| Embedded scripting (mlua / rhai) | User-script territory, not extension territory. Not for Plamenix. |

See [adr/0003-wasm-component-model-plugins.md](./adr/0003-wasm-component-model-plugins.md).

## Toolchain

- **Runtime**: `wasmtime` (Component Model 1.0, WASI Preview 2).
- **Contract**: WIT files, generated bindings via `wit-bindgen` for
  Rust + TypeScript.
- **Rust SDK**: `plamenix-plugin-sdk` published to crates.io. Thin
  macros over `wit-bindgen`.
- **TypeScript SDK**: `@plamenix/plugin-react` published to npm.
  Exposes `usePluginAPI<API>()` hook and `<PluginOutlet point="..."/>`
  slot component.

## Plugin author language

**Rust only for v1.0.x.** WIT is language-agnostic; future SDKs in Go /
JS / Python are technically possible via the Component Model, but
official support is Rust only at `1.0.0`. Additional SDKs land when
community demand arises and core-team expertise covers them.

The UI half is always TypeScript / React because that is how browsers
work. Plugins are therefore bi-lingual (Rust + TS) by design, but Rust
is the only "extension language" decision.

## Bundle layout

```
my-plugin/
├── manifest.toml             # metadata, capabilities, contributions
├── rust/
│   ├── Cargo.toml            # depends on plamenix-plugin-sdk
│   └── src/lib.rs            # #[plugin_export] functions
├── ui/
│   ├── package.json          # depends on @plamenix/plugin-react
│   ├── src/index.tsx
│   └── tsconfig.json
└── dist/                     # build output, packed into .plx
    ├── plugin.wasm
    ├── ui.mjs
    └── manifest.toml
```

`plamenix-cli` (future) scaffolds (`create-plamenix-plugin`), builds
both halves, and packs the `.plx` archive.

## Loading flow

1. Host scans plugin directories (`~/.plamenix/plugins/` on desktop;
   admin-managed path on web edition).
2. Each `manifest.toml` is parsed and validated against the host's
   minimum version and supported `plugin_api` interface version.
3. Plugin UI contributions are registered in an in-memory registry
   queried by `<PluginOutlet>` components in the React shell.
4. The WASM module is **not** instantiated until first invocation; this
   keeps cold-start fast even with many plugins installed.
5. Plugin invocations are gated by the capability checker before each
   host function call.
6. Failures are isolated: a plugin trap returns a clean error to the
   caller; the host process never crashes from a plugin fault.

## Versioning policy

- **Plugin host** version follows Plamenix's SemVer line.
- **`plugin_api` WIT interface** is independently versioned. Breaking
  changes mint a new interface version (`plugin-api@1.0`,
  `plugin-api@2.0`); the host binds multiple versions simultaneously so
  old plugins keep working.
- Deprecated functions are marked `#[deprecated]` in the SDK and kept
  for at least three minor releases before removal.
- Capability additions are backward-compatible — old plugins that do
  not request a new capability are unaffected.

See [plugin-manifest.md](./plugin-manifest.md) for the manifest schema
and [capability-model.md](./capability-model.md) for permission grammar.
