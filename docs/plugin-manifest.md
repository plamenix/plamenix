# Plugin manifest

Every Plamenix plugin ships a `manifest.toml` at the root of its `.plx`
bundle. The manifest is the single source of truth for plugin metadata,
host compatibility, requested capabilities, and contribution points.

A JSON Schema (Draft 2020-12) describing the manifest lives at
`plamenix-core/crates/plamenix-plugin-host/schema/manifest.schema.json`
and is published canonically at
`https://plamenix.dev/schemas/plugin-manifest-1.0.0.json`. Editors that
support TOML schema hints (e.g. `taplo`, the JetBrains TOML plugin)
pick it up automatically when the manifest's first non-blank line is:

```
#:schema https://plamenix.dev/schemas/plugin-manifest-1.0.0.json
```

The host's `Manifest::parse` performs the runtime validation; the JSON
Schema serves authoring tools (autocomplete, hover docs, IDE diagnostics,
external CI lints) and is kept in lockstep with the Rust types.

## Schema

```toml
[plugin]
id = "org.example.csv-exporter"            # reverse-DNS identifier, unique
name = "CSV Exporter"                       # display name
version = "1.0.0"                           # plugin's own SemVer
plamenix_min_version = ">=1.0.0-beta"       # host version range
plugin_api = "1.0"                          # WIT interface version targeted
author = "Author Name <email@example.com>"
license = "MIT OR Apache-2.0"
homepage = "https://example.org/csv-exporter"
description = "Export tables to CSV with custom delimiters."

[permissions]
required = [
    "db.read.any",
    "export.format",
]
optional = [
    "net.https.example.com",
]

[entry_points]
wasm = "dist/plugin.wasm"                   # Rust half, relative to bundle root
ui   = "dist/ui.mjs"                        # React half, relative to bundle root

[runtime]
requires_subprocess = false                 # true only for plugins needing raw OS access

[contributions.ui]
sidebar_panels = [
    { id = "csv-export", label = "Export to CSV",
      component = "ExportPanel", icon = "download" },
]
context_menu = [
    { target = "table_row", label = "Export as CSV…",
      command = "csv.export" },
]
table_viewers = []

[contributions.db]
# Optional: register a dialect converter or driver.
# dialect_converters = [{ id = "fb-to-csv", source = "firebird", target = "csv",
#                         handler = "convert_dump" }]
```

## Required fields

The host refuses to load a plugin missing any required field:

- `plugin.id` — reverse-DNS, unique, immutable after first publish.
- `plugin.name` — human-readable.
- `plugin.version` — SemVer.
- `plugin.plamenix_min_version` — SemVer range Plamenix host must
  satisfy.
- `plugin.plugin_api` — WIT interface version this plugin targets.
- At least one of `entry_points.wasm` or `entry_points.ui`.

## `plugin_api` version

The host can load plugins targeting multiple WIT interface versions
simultaneously. Breaking changes mint a new interface version
(`plugin-api@1.0` → `plugin-api@2.0`); plugins targeting `1.0` continue
to work for at least three minor host releases after `2.0` ships.

The first interface version frozen at `1.0.0-rc.1`.

## Capability declaration

Capabilities are declared in `[permissions]`:

- `required` — without them, the plugin will not load. The user sees
  the requested set at install time and can Allow / Deny / Customize.
- `optional` — runtime-gated. The plugin must handle
  `PluginError::PermissionDenied` for these.

Capability grammar lives in [capability-model.md](./capability-model.md).

## Entry points

- `entry_points.wasm` — path to the compiled WASM Component
  (`wasm32-wasip2` target). Loaded by the host's `wasmtime` runtime
  on first invocation, not eagerly at startup.
- `entry_points.ui` — path to the ESM bundle. Loaded by dynamic
  `import()` when a slot the plugin contributes is first rendered.

## Contribution points

`[contributions.ui]` and `[contributions.db]` enumerate the slots the
plugin fills. Allowed keys are the bounded set described in
[contribution-points.md](./contribution-points.md). Unknown keys cause
the manifest to be rejected.

## Trust tiers

Plamenix categorises plugin sources by trust:

- **Official** — maintained by the Plamenix team. Audited. Marked with
  an official badge in the plugin manager UI.
- **Verified** — community-reviewed, signed by the Foundation. Subject
  to a review process.
- **Community** — anyone publishes. Install dialog shows an orange
  warning highlighting the requested capabilities.
- **Sideload** — installed from a local folder, no signature. Allowed
  only in developer mode. Red warning.

The trust tier is determined by the source registry and signature
attached to the bundle, not by the manifest itself.

## Tooling

- `plamenix-cli build` packs source into a `.plx` archive and validates
  the manifest.
- `plamenix-cli publish` (when registry is live) uploads to a chosen
  trust tier.
- `plamenix-cli sideload <path>` installs a local `.plx` for
  development.
