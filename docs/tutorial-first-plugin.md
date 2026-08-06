# Write your first Plamenix plugin

A 30-minute walkthrough that takes you from `plamenix new` to a
signed `.plx` installed on either Plamenix edition. By the end you
have a real plugin that adds a sidebar panel saying "Hello from my
first plugin" and a Rust half that logs a line at activation.

> **Audience.** You know Rust + React at a "hello world" level. You
> have `cargo` and `npm` (or `pnpm`) installed.
> **Time.** 20 – 40 minutes depending on toolchain warm-up.
> **Result.** One `.plx` that runs on both editions, signed with a
> key you generate locally.

If you want the wider system picture first, read
[`plugin-architecture.md`](./plugin-architecture.md) and
[`plugin-system.md`](./plugin-system.md). For deep references see
[`plugin-authoring.md`](./plugin-authoring.md) (manual recipe) +
[`capability-model.md`](./capability-model.md) (permission grammar).

---

## 0. Install the toolchain

Once per machine:

```sh
# Rust nightly is NOT required. The plugin target is wasm32-wasip2,
# stable since Rust 1.95 (the version pinned by plamenix-core).
rustup target add wasm32-wasip2

# plamenix-cli ships from the plamenix-core workspace. Build it
# locally for now; once published you'll `cargo install plamenix-cli`.
cd ~/Code/plamenix-core
cargo install --path crates/plamenix-cli --force

# Verify.
plamenix --version
# > plamenix 1.0.0-beta
```

If you're inside the Plamenix repo you can also run `cargo run -p
plamenix-cli --` to invoke the binary without installing.

---

## 1. Scaffold the plugin

```sh
plamenix new dev.example.first-plugin \
  --name "First Plugin" \
  --description "My first Plamenix plugin." \
  --author "You <you@example.com>"
```

This creates a directory `dev.example.first-plugin/` populated with
six files:

```text
dev.example.first-plugin/
├── manifest.toml      # Validated by the host loader.
├── Cargo.toml         # cdylib targeting wasm32-wasip2.
├── package.json       # UI half — React + @plamenix/ui peer.
├── src/
│   ├── lib.rs         # Rust plugin entry. TODO body.
│   └── ui.tsx         # React UI entry. TODO body.
└── README.md          # Build instructions + commands.
```

`cd dev.example.first-plugin/` and skim `manifest.toml`. It declares:

- `id = "dev.example.first-plugin"` — globally unique.
- `version = "0.1.0"` — bump on every publishable change.
- `targets = ["desktop", "web"]` *(implicit default)* — runs on
  both editions.
- `entry_points.wasm = "plugin.wasm"` + `entry_points.ui = "ui.mjs"` —
  the host loads both halves at activation.
- `[permissions]` — empty for now. We'll add a permission later.

### Validate the scaffold

```sh
plamenix validate .
```

You should see:

```text
First Plugin (dev.example.first-plugin) v0.1.0
  api:       1.0
  entries:   wasm, ui
  perms:     0 required, 0 optional
  subproc:   no
```

If you get a parser error, the scaffold's manifest grammar drifted
from the host's loader. Open an issue on `plamenix-core` with the
message — the I7.11 + I7.14 scaffold tests should catch that before
release.

---

## 2. Fill in the Rust half

Open `src/lib.rs`. The scaffold body is a TODO stub:

```rust
#[allow(dead_code)]
fn activate() -> Result<(), &'static str> {
    Ok(())
}
```

Replace it with a real `activate()` that logs a line via the host's
`log` import. (The SDK is a path dep until the first public release;
see `plamenix-plugin-sdk` in the workspace.)

```rust
//! First Plamenix plugin — Rust half.

use plamenix_plugin_sdk::host::log;

#[allow(dead_code)]
fn activate() -> Result<(), &'static str> {
    log!(Info, "hello from my first plugin");
    Ok(())
}
```

> **Why a macro.** `host::log!` wraps the WIT-generated `host.log`
> import + does the level-enum conversion. Plain `host::log(...)`
> works but you have to import `LogLevel` yourself.

Add the SDK dep to `Cargo.toml`:

```toml
[dependencies]
plamenix-plugin-sdk = { path = "../../plamenix-core/crates/plamenix-plugin-sdk" }
```

> Until the SDK ships to crates.io, `path =` is the simplest
> wiring. Swap to a SemVer range once published.

---

## 3. Fill in the UI half

Open `src/ui.tsx`. The scaffold registers nothing. We'll add a
sidebar panel.

```tsx
/// <reference types="react" />
import type { ActivePluginApi } from '@plamenix/ui';

export default function activate(api: ActivePluginApi) {
  api.registerSidebarPanel({
    id: 'hello-panel',
    label: 'Hello',
    icon: 'sparkles',
    render: () => <HelloPanel />,
  });
}

function HelloPanel() {
  return (
    <div className="p-4">
      <h2 className="text-lg font-semibold">Hello from my first plugin</h2>
      <p className="text-sm text-fg-muted">
        Edit <code>src/ui.tsx</code> and re-run <code>plamenix build</code>.
      </p>
    </div>
  );
}
```

Install the peer dependencies the scaffold's `package.json` declares:

```sh
npm install
```

> **Pnpm users.** `pnpm install` works too. The CLI detects
> `pnpm-lock.yaml` at build time and switches package managers
> automatically.

---

## 4. Build the bundle

```sh
plamenix build
```

The CLI walks four steps:

1. Parses `manifest.toml`.
2. Runs `cargo build --target wasm32-wasip2 --release` and copies
   the resulting `.wasm` to `plugin.wasm`.
3. Runs `npm run build` and copies `dist/ui.mjs` → `ui.mjs`.
4. Packs everything into `dev.example.first-plugin-0.1.0.plx`.

On success it prints:

```text
built ./dev.example.first-plugin-0.1.0.plx (wasm: yes, ui: yes)
```

If a step fails:

- `cargo build failed (...)` — the Rust half didn't compile. Read
  the captured stderr the CLI prints.
- `npm/pnpm build failed (...)` — the UI half didn't bundle. Run
  the same `npm run build` command directly to see the full
  vite output.
- `ui bundle not produced` — your `package.json` build script
  emits the bundle to a non-standard path. Configure vite's
  `outDir: "."` + `output.entryFileNames: "ui.mjs"`, or drop the
  built file at the top level yourself.

If you don't need to rebuild (e.g. CI produced the artifacts in an
earlier step), pass `--skip-wasm --skip-ui` to skip both build halves
and only repack.

---

## 5. Sign the bundle

Unsigned plugins install with a red banner; users have to explicitly
trust them. Generate a signing key once + reuse it across releases:

```sh
plamenix keygen ~/.config/plamenix/my-key
# > secret: ~/.config/plamenix/my-key
# > public: ~/.config/plamenix/my-key.pub (abcd1234…)
```

The secret file is mode `0600`; treat it like an SSH private key
(don't commit it, don't share it).

Sign the bundle:

```sh
plamenix sign dev.example.first-plugin-0.1.0.plx \
  --key ~/.config/plamenix/my-key \
  --key-id "you@example.com"
```

Now `plamenix validate` shows a signed bundle:

```sh
plamenix validate dev.example.first-plugin-0.1.0.plx
# > First Plugin (dev.example.first-plugin) v0.1.0
# >   api:       1.0
# >   entries:   wasm, ui
# >   perms:     0 required, 0 optional
# >   subproc:   no
```

The host verifies the signature on install. Tampering with the
archive between sign + install invalidates the signature and the
host refuses the bundle.

> **Signing layer details.** See
> [`plugin-system.md`](./plugin-system.md) §7. The format is
> Ed25519; the `signature.json` member covers a SHA-256 digest of
> every other file in the archive.

---

## 6. Install

### Desktop (Tauri shell)

1. Open Plamenix.
2. `View → Plugins → Install plugin…` opens a file picker.
3. Pick the `.plx`. The install dialog shows the manifest summary +
   the signature status (verified emerald, or "no signature" red).
4. Click **Install**. The plugin activates immediately; your
   sidebar shows a new "Hello" entry.

### Web (Fastify server, admin only)

Web installs go through `POST /api/plugins/install`. The endpoint
accepts a JSON body `{ bundleBase64, grantedOptional }`. Until the
CLI's HTTP client ships (M2), upload manually with `curl`:

```sh
BUNDLE_B64=$(base64 < dev.example.first-plugin-0.1.0.plx)
curl -X POST https://your-plamenix.example/api/plugins/install \
  -H 'Content-Type: application/json' \
  -d "{\"bundleBase64\": \"$BUNDLE_B64\", \"grantedOptional\": []}"
```

The server returns the staged plugin + activation status. Refresh
the web shell — your sidebar panel should appear.

---

## 7. Add a permission

Real plugins read state. Add the `db.read.any` permission so your
plugin can list tables:

```toml
# manifest.toml
[permissions]
required = [{ capability = "db.read.any" }]
optional = []
```

Re-run `plamenix build` then re-sign. On install, the dialog now
shows a **Required permissions** batch with `db.read.any` and the
user must accept it (or cancel) before the install proceeds.

The full capability grammar lives in
[`capability-model.md`](./capability-model.md). The short version:

- `db.read.any` / `db.write.any` / `db.ddl.any` — table-level CRUD.
- `db.read.table.<name>` — scope to one table.
- `db.schema.list` / `db.schema.describe` — metadata.
- `net.https` / `net.https.<host>` — outbound HTTPS.
- `runtime.subprocess` — opt out of the WASM sandbox (rare).

---

## 8. Iterate

`plamenix build` is fast enough for tight loops. Common patterns:

- **UI-only changes** — `plamenix build --skip-wasm` (skips the
  cargo invocation entirely).
- **Rust-only changes** — `plamenix build --skip-ui --skip-install`.
- **CI caching** — run `plamenix pack .` after your CI's build step
  to assemble a `.plx` without re-invoking cargo / npm.

---

## 9. Where to go next

- [`plugin-events.md`](./plugin-events.md) — the 28 event topics
  your plugin can subscribe to.
- [`plugin-interceptors.md`](./plugin-interceptors.md) — the 8
  policy chains for blocking destructive actions before they
  execute.
- [`contribution-points.md`](./contribution-points.md) — every
  surface you can extend (cell renderers, commands, settings
  panels, schema actions, …).
- [`plugin-manifest.md`](./plugin-manifest.md) — every manifest
  field with examples.

When you're ready to publish, follow the release flow:

1. Bump `version` in `manifest.toml`, `Cargo.toml`, and
   `package.json`.
2. `plamenix build`.
3. `plamenix sign … --key-id "release-1.0.0"`.
4. Distribute the resulting `.plx` (GitHub release, your own CDN,
   or upload through the web edition's admin endpoint).

The community channel and ecosystem links live in
[`plugin-system.md`](./plugin-system.md) §10.
