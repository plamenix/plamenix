# Capability model

Plugins request capabilities in their `manifest.toml`. The host gates
every plugin call against the granted set. Denied calls surface as
`PluginError::PermissionDenied` to the plugin, which handles them
gracefully. The host never crashes from a permission failure.

The model is inspired by Tauri's capability system and Deno's explicit
grant model.

## Capability grammar

A capability is a dotted name with optional scope:

```
<resource>.<action>[.<scope>]
```

Examples:

```
db.read.any                                 # read every table
db.write.table.users                        # write only to the "users" table
export.format                               # produce any export format
net.https                                   # any HTTPS endpoint
net.https.api.example.com                   # only api.example.com
fs.read.dir.downloads                       # only ~/Downloads
fs.write.dir.plugin-data                    # only plugin's private data dir
auth.os.windows                             # Windows Credential Manager
auth.os.macos                               # macOS Keychain
clipboard.read
clipboard.write
runtime.subprocess                          # implies requires_subprocess=true
```

Wildcards are not supported. Each capability that matters must be
listed explicitly. This prevents accidental over-granting via broad
patterns.

## Capability classes

### Database
- `db.read.any`, `db.read.table.<name>`
- `db.write.any`, `db.write.table.<name>`
- `db.ddl.any`, `db.ddl.table.<name>`
- `db.txn.<isolation>` — explicit transaction isolation level
- `db.schema.list`, `db.schema.describe`

### Export / import
- `export.format` — register or invoke an export format
- `import.source` — register or invoke an importer

### Network
- `net.https`, `net.https.<host>`
- `net.http` — discouraged; requires user confirmation
- `net.outbound.<protocol>` — for non-HTTP protocols

### Filesystem
- `fs.read.dir.<id>` — `id` ∈ {`downloads`, `documents`, `temp`,
  `plugin-data`, `plugin-config`}
- `fs.write.dir.<id>`
- Absolute paths are never granted directly; plugins receive logical
  directory aliases that the host resolves.

### Auth
- `auth.os.windows`, `auth.os.macos`, `auth.os.linux-keyring`
- `auth.session.read`, `auth.session.write`

### Clipboard / OS
- `clipboard.read`, `clipboard.write`
- `os.notify` — show OS notification
- `os.open-url` — request the OS open a URL

### Runtime
- `runtime.subprocess` — must be paired with
  `runtime.requires_subprocess = true` in the manifest; granting it
  drops the plugin out of the WASM sandbox into a separate subprocess
  with full IPC isolation. Triggers a stricter install-time warning.

## Install-time consent

At install, the user sees a dialog summarising requested capabilities:

```
CSV Exporter wants permission to:
  ✓ Read any database table          (db.read.any)
  ✓ Produce export formats           (export.format)
  ? Make HTTPS requests              (net.https)
[Allow]  [Deny]  [Customize…]
```

`Customize` opens a fine-grained view where the user can grant or deny
each capability individually, including narrowing wildcard requests
(e.g., grant `net.https.api.example.com` only).

## Runtime enforcement

- The host maintains the granted capability set per plugin instance.
- Each host function exposed via WIT performs a capability check before
  executing.
- Failed checks return `PluginError::PermissionDenied`. The plugin can
  observe the error and either:
  - Fail gracefully and surface a clear message to the user.
  - Request elevation via a host helper (which prompts the user).

## Manifest enforcement

- A capability used at runtime but absent from `permissions.required`
  or `permissions.optional` is treated as an error: the host refuses
  the call and emits a strong warning. This prevents capability
  smuggling.

## Trust tiers and capability default-deny

| Trust tier | Default for risky capabilities |
|------------|--------------------------------|
| Official | Granted at install with confirmation. |
| Verified | Granted at install with confirmation. |
| Community | Defaults to deny for `net.*`, `fs.*`, `runtime.subprocess`; user must explicitly opt in. |
| Sideload | Same as community; install dialog adds a "developer mode only" warning. |

The capability set requested in the manifest is the **maximum** a plugin
can use; the granted set may be smaller.
