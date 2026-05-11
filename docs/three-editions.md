# Two editions, one shell

Plamenix ships in two editions that share a single React UI library:

- **Desktop edition** (`plamenix-desktop`) — Tauri 2 application
  bundling the Rust core directly. Single-user, in-process, full OS
  access.
- **Web edition** (`plamenix-web`) — Fastify (Node) server with the
  React UI served as a static bundle. Multi-user, self-hostable on a
  server, browser-side UI. Talks to Firebird through a NAPI binding
  to rsfbclient.

The React shell (`@plamenix/ui`) is identical between editions. The
edition chooses the `Transport` implementation at boot and advertises
its `HostCapabilities` descriptor; components hide or disable
features not available in the current edition.

## Capability matrix

| Capability | Desktop | Web |
|------------|---------|-----|
| Connect to remote Firebird | ✓ | ✓ |
| Pure-Rust rsfbclient fallback | ✓ | ✓ |
| Bundled native fbclient | ✓ | ✓ (server-side) |
| Discover local `.fdb` via filesystem scan | ✓ | ⚠ server filesystem only |
| `docker exec` discovery of `databases.conf` aliases | ✓ | ⚠ server-side, may be disabled by admin |
| Save password to OS keyring | ✓ (opt-in) | ✗ — keys remain in-memory per session |
| Splash window | ✓ | inline loading state in main page |
| System tray + native menus | ✓ | ✗ |
| Auto-updater | ✓ | manual (admin upgrades server) |
| Multi-user authentication | ✗ (single user) | ✓ (sessions / JWT / cookies) |
| Plugin install scope | per-user, `~/.plamenix/plugins/` | admin-managed, server-side |
| Export → user's `~/Downloads` | ✓ direct write | ⚠ browser download |
| Native dialog (file picker, etc.) | ✓ via Tauri | ⚠ browser dialog only |
| Multi-window (future) | ✓ (Tauri) | ✗ |
| Drag-drop OS file into editor | ✓ | ✓ (limited) |
| Clipboard read/write | ✓ | ⚠ user permission required |

## Edition-specific code lives in the edition's repo

- `plamenix-desktop/` — Tauri commands (`#[tauri::command]`), splash
  window, native fbclient bundling per platform, OS keychain
  integration, auto-updater wiring, system tray.
- `plamenix-web/` — Fastify routes (`/api/<command>`), session
  management, authentication, server-side plugin store, Docker image,
  NAPI binding to rsfbclient.
- `plamenix-ui/` — components, hooks, stores, transport interface.
  Imports nothing from Tauri or Node.
- `plamenix-core/` — Rust crates shared between desktop (used
  directly) and web (used via NAPI). Has no awareness of which
  edition is running.

## Capability query API

```ts
// React side
const canUseKeyring = useCapability('keychain');
const canShowSystemTray = useCapability('systemTray');
const isMultiUser = useCapability('multiUser');
```

Components conditionally render UI based on the capability set:

```tsx
{canUseKeyring && (
  <Checkbox label="Save to OS keyring" checked={save} onChange={setSave} />
)}
```

## Single source of truth for backend logic

The use cases (connect, query, list schema, export, plugin invocation)
live in `plamenix-core`. Both editions wire them up to their transport:

- Desktop: `#[tauri::command]` handlers in `plamenix-desktop/src-tauri/`
  call into `plamenix-core` directly.
- Web: Fastify routes in `plamenix-web/` call NAPI bindings exposing
  the same use cases.

A new feature in `plamenix-core` is automatically available to both
editions; only the thin shell wiring differs.

## Why not a single edition

Two editions explicitly because the constraints differ:

- Desktop benefits from native code paths (filesystem scan, OS
  keychain, auto-updater) that have no clean browser analogue.
- Web benefits from multi-user hosting, browser portability, and a
  zero-install path for administrators.

Trying to collapse them into one binary that does both would compromise
both. Keeping them separate but sharing the UI library and core crates
is the modern compromise.
