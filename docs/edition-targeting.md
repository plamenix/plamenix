# Edition targeting guide

Every Plamenix plugin declares which editions it runs on via the
manifest's `targets` field:

```toml
[plugin]
targets = ["desktop", "web"]   # default: both
```

This guide helps plugin authors pick the right value. For background
on what each edition actually is, see
[`architecture.md`](./architecture.md) and
[`three-editions.md`](./three-editions.md).

## TL;DR decision tree

```text
Does your plugin call os-level APIs?
├─ Yes (Keychain, system tray, file picker, native CLI)
│  └─ targets = ["desktop"]
└─ No
   └─ Does your plugin assume server-mediated state?
      ├─ Yes (multi-user grants, admin endpoints, shared profiles)
      │  └─ targets = ["web"]
      └─ No (pure SQL transform, UI contribution, lint, formatter)
         └─ targets = ["desktop", "web"]   # default
```

**Default to both.** A plugin that targets only one edition cuts its
audience in half. Only restrict when something concrete makes the
plugin nonsensical on the other side.

## What each edition gives you

| Capability | Desktop (Tauri) | Web (Fastify) |
|---|---|---|
| **Runtime** | Tauri webview + Rust commands | Fastify HTTP + React SPA |
| **Filesystem access** | Per-OS dirs via Tauri | Server-side only, plugin-data dir |
| **OS keyring** | macOS Keychain / Windows Credential Manager / Linux Secret Service | Server-side `plamenix-secrets`, never user-visible |
| **System tray / notifications** | Yes | No |
| **Native file picker** | Yes (Tauri dialog) | Browser file input only |
| **Subprocess plugins** | Yes (single-process host spawns the binary) | Yes (server spawns; clients see results over HTTP) |
| **`net.https` from plugin** | Direct from sandboxed runtime | Direct from server; client sees responses via the host import |
| **Concurrent users** | One (the running shell) | Many (Fastify session per user) |
| **Admin endpoints** | Tauri commands the shell calls | HTTP routes the admin operator hits |
| **Sandbox** | wasmtime, per-plugin Store, I8 limits | wasmtime via napi binding, same per-plugin Store, same I8 limits |

The Rust plugin host (`plamenix-plugin-host`) is the SAME in both
editions. Capability enforcement, supervisor behaviour, signature
verification — all identical. What differs is the surface that
sits ABOVE the host (Tauri command bridge vs Fastify routes) and
what those surfaces let plugins reach through host imports.

## When to pick `targets = ["desktop"]`

Pick desktop-only when your plugin *needs* something the web edition
structurally cannot provide:

- **OS-native UI affordances** — system tray icon, native menubar,
  global hotkeys, OS notifications.
- **OS keyring write access** — desktop plugins can write to
  Keychain/Credential Manager/Secret Service via the host's
  `auth.os.*` capabilities (M2). The web edition's `plamenix-secrets`
  store is server-internal and not user-visible.
- **Native binary invocation** — desktop subprocess plugins ship the
  binary inside the `.plx` and run it locally with the calling
  user's OS identity. The web edition runs subprocess plugins on
  the SERVER, with the server's identity — fine for some tools,
  wrong for "use my SSH agent" style features.
- **Single-user assumptions** — desktop is single-tenant by
  construction. A plugin that keeps per-user state in WASM linear
  memory works correctly on desktop. The same plugin on web
  shares state across every user hitting that server — a
  correctness bug.
- **Filesystem reach beyond plugin storage** — desktop plugins can
  request paths via the host's `fs.*` capabilities (M2). Web has
  no analog by design; the server's filesystem belongs to the
  operator, not the plugin.

**Symptom that you should be desktop-only:** "this plugin assumes
exactly one user is running it and that user owns the host
machine."

## When to pick `targets = ["web"]`

Pick web-only when your plugin *needs* the server-mediated model:

- **Admin endpoints** — `POST /api/plugins/...` style operations
  that only the server-side operator should hit. The desktop
  edition has no equivalent surface.
- **Shared profiles / grants** — web's grant store is SQLite-backed
  + admin-managed. A plugin that needs "every user sees the same
  granted capabilities" doesn't fit desktop's single-tenant model.
- **Cross-user audit log** — web sees every client request; desktop
  only sees its own. Audit plugins that need a server-level view
  belong on web.
- **Database-export server orchestration** — large-bundle exports
  with progress that fans out to multiple clients work cleanly on
  web; desktop's single-shell model has no concept of "fan out".

**Symptom that you should be web-only:** "this plugin assumes a
server-side operator manages state that multiple users observe."

## When to pick `targets = ["desktop", "web"]` (the default)

Pick both — and **this is the default** — when the plugin's logic
doesn't depend on which edition is hosting it:

- **Cell renderers** — JSON viewer, BLOB previewer, custom date
  formatters. All pure UI; no edition-specific reach.
- **SQL formatters / linters / completion providers** — pure
  transforms over text + schema.
- **Schema-action plugins** — DDL generators, table-recreate
  wizards. Both editions expose the same `db.ddl.*` capabilities.
- **Dashboard cards / status-bar items** — UI surfaces hosted in
  React; the React tree is the same on both editions.
- **Theme plugins** — pure CSS / palette overrides.
- **Import sources** — pull CSV/JSON/Parquet → INSERT. The pull
  side reads bytes the user supplied; the INSERT side hits the
  `db.write.*` capability the host exposes uniformly.

The JSON cell renderer that I9.2 smoke-tests is the canonical
example of a both-editions plugin: zero edition-specific surface,
same `.plx` runs unchanged on either edition.

## What enforcement looks like

`targets` is enforced at two points:

1. **Host bootstrap** — both editions filter their plugin scan
   through `staged.targets.includes(<edition>)` before activation.
   Plugins whose declared targets exclude the current edition land
   in the bootstrap's `failures` array with reason `"plugin targets
   ["desktop"] but this edition is "web""`. They never reach the
   activator.
2. **Install endpoint** (web) — the `POST /api/plugins/install`
   route validates the manifest before persisting the bundle to
   disk. Manifests targeting only `desktop` get rejected at install
   time with a 4xx response.

See `plamenix-plugin-host/tests/targets_enforcement.rs` for the
host-side predicate matrix (7 tests) and
`plamenix-web/packages/server/test/plugins/edition-mismatch.test.ts`
for the bootstrap-level skip test.

## Edge cases

### Subprocess plugins that ship per-OS binaries

A subprocess plugin's binary is OS-specific. Two options:

1. **Multiple bundles** — one `.plx` per `(edition × OS)`. The
   plugin id stays the same; the user installs whichever bundle
   matches their environment. The host accepts any of them; only
   one can be loaded at a time per plugin id.
2. **One bundle, conditional manifest** — ship every per-OS binary
   under `bin/<os>/<arch>/plugin` and select at activation. The
   manifest's `entry_points.subprocess` MUST be a single string
   today, so this requires a tiny launcher binary. **Not
   recommended.**

For M1, ship per-OS bundles (#1). The CLI's `plamenix build`
doesn't help with cross-compilation yet; CI matrix-builds and
packs each combination separately.

### Plugin needs partial overlap

You want desktop's keyring AND web's admin endpoint. Don't merge
them into one plugin. Ship two plugins with related ids:

- `org.example.my-tool` — `targets = ["desktop"]`, the keyring half.
- `org.example.my-tool-admin` — `targets = ["web"]`, the admin half.

Cross-reference them in each `README.md`. The host has no concept
of "plugin family", so the convention is documentation-only.

### Plugin works today on both, may need edition-specific features later

Default `targets = ["desktop", "web"]` and don't pre-emptively
restrict. When the edition-specific need arrives, version-bump and
restrict in the new version. Old installs continue to work; new
installs see the restricted set.

## Migration: changing `targets` between versions

| Change | Effect on existing installs | Effect on new installs |
|---|---|---|
| `["desktop", "web"]` → `["desktop"]` | Web installs stay running for the lifetime of the host session; the bootstrap on next start refuses them. | Web edition refuses install. |
| `["desktop"]` → `["desktop", "web"]` | No effect on existing desktop installs. | Web edition accepts install. |
| `["web"]` → `["desktop", "web"]` | No effect on existing web installs. | Desktop edition accepts install. |

A plugin that restricts its targets between minor versions should
bump the MAJOR version per SemVer — restricting is a breaking
change for the users on the now-excluded edition.

## Quick checklist

Before publishing your `.plx`:

- [ ] Does your plugin call OS APIs the WASM sandbox doesn't expose?
      → `targets = ["desktop"]`.
- [ ] Does your plugin assume multi-user / server-mediated state?
      → `targets = ["web"]`.
- [ ] Neither? → `targets = ["desktop", "web"]` (the default).
- [ ] Does your plugin ship per-OS subprocess binaries?
      → Ship one `.plx` per `(edition × OS)`.
- [ ] Are you restricting `targets` between minor versions?
      → Bump MAJOR per SemVer.

## See also

- [`tutorial-first-plugin.md`](./tutorial-first-plugin.md) — the
  walkthrough that scaffolds a both-editions plugin by default.
- [`plugin-manifest.md`](./plugin-manifest.md) — full `targets`
  field syntax + the `Edition` enum's accepted values.
- [`three-editions.md`](./three-editions.md) — desktop vs web
  capability matrix at the host level.
- [`architecture.md`](./architecture.md) — why the polyrepo split +
  why the editions share a host.
