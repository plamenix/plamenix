# Capability model

Plugins request capabilities in their `manifest.toml`. The host gates
every plugin call against the granted set. Denied calls surface as
`PluginError::PermissionDenied` to the plugin, which handles them
gracefully. The host never crashes from a permission failure.

The model is inspired by Tauri's capability system and Deno's explicit
grant model.

## Enforcement layers

There is no single enforcement choke point. Capabilities are checked
at four distinct moments, each closing a different class of leak:

1. **Manifest parse time** — `Manifest::parse` runs the grammar over
   every capability string and enforces the structural rules. Failures
   surface as `PluginError::InvalidCapability` before the plugin ever
   reaches the activator. Coverage: every code path that loads a
   manifest, including the loader, the install endpoint, and
   `plamenix validate`.
2. **Install-time consent** — the install dialog (I7.1) shows required
   permissions as a batch + optional permissions as a collapsed
   disclosure with per-permission checkboxes. The user either accepts
   the entire required batch or cancels; the optional subset they tick
   is recorded as the initial grant set.
3. **First-use prompt** — when a plugin tries to use an optional
   permission that the user skipped at install time (I7.2), a runtime
   prompt offers `Allow once` / `Allow always` / `Deny`. `Allow always`
   persists; `Allow once` satisfies a single call without persisting.
4. **Runtime gate** — each host function exposed via WIT performs a
   capability check before doing the actual work. Failed checks return
   `PluginError::PermissionDenied`. The plugin can recover gracefully
   or surface a clear error.

The host's `Supervisor` (I8.1) and `InstanceRegistry` (I8.2) are
NOT in the enforcement path; they manage lifecycle, not access. The
Permissions panel (I7.3) reads the current grant set + lets the user
revoke optional permissions; revocation takes effect on the next
host call.

## Capability grammar

A capability is a dotted name with optional scope:

```
<resource>.<action>[.<scope>]
```

Examples (the full Rust `Permission` enum is the source of truth):

```
db.read.any                                 # read every table
db.write.any                                # write every table
db.ddl.any                                  # DDL on every table
db.schema.list                              # list tables/views/procedures
db.schema.describe                          # describe one object's columns
net.https                                   # any HTTPS endpoint
net.https.<host>                            # only one HTTPS host
```

Wildcards are NOT supported. Each capability that matters must be
listed explicitly. This prevents accidental over-granting via broad
patterns.

The full enumeration ships in
[`plamenix-plugin-host/src/capability.rs`](https://github.com/plamenix/plamenix-core/blob/main/crates/plamenix-plugin-host/src/capability.rs).
Adding a capability there requires:

1. Adding the variant to the `Permission` enum.
2. Wiring its parse arm in `Permission::parse`.
3. Wiring its `Display` arm.
4. Adding the runtime gate at the host-import call site that consumes
   it.

## Capability classes

Every class below has a host import behind it and a runtime gate at the
call site. The list is derived from the `impl ... Host for HostState`
blocks in `plamenix-plugin-host/src/imports/` and the `Permission::`
checks inside them; if you are changing one, change both.

This section previously marked filesystem, auth and clipboard as
**(M2)** — "grammar exists, no runtime gate yet". That stopped being
true when the host import surface landed in Wave 4, and the filesystem
entry additionally pointed readers at subprocess plugins as the
workaround, which had been deleted a wave earlier.

### Database — `db.rs`

- `db.read.any`, `db.write.any`, `db.ddl.any`
- `db.schema.list`, `db.schema.describe`
- `db.session.context.read`

Table-scoped forms (`db.read.table.<name>` and friends) are **refused
by the parser**, with a message naming the capability to declare
instead. Enforcing them means knowing which tables a statement touches,
which means parsing SQL; accepting them ungated would grant everything
while naming one table.

They used to parse, which was the worst of the three options: no call
site accepts the table-scoped form, so the install dialog asked the user
to approve `db.read.table.CUSTOMERS`, they approved it, and every
subsequent db call was denied.

### Filesystem — `fs.rs`

- `fs.read.dir.<id>`, `fs.write.dir.<id>`

Logical directories only: `plugin-data`, `plugin-config`, `downloads`,
`documents`, `temp`. The host owns the jail and resolves paths itself
rather than handing plugins `wasi:filesystem`, which would be a
strictly larger grant than any of these.

### Settings — `settings.rs`

- `settings.read`, `settings.write`

Plugin-scoped, not user-scoped. On the web edition that distinction
matters and is not yet made — recorded in the remediation plan rather
than solved.

### Network, clipboard, notifications, secrets, commands, events — `misc.rs`

- `net.https`, `net.https.<host>`, `net.http`
- `clipboard.read`, `clipboard.write`
- `os.notify`
- `secrets.read.service.<service>`, `secrets.write.service.<service>`
- `command.invoke`
- `event.publish.<channel>`

The `net` transport is the shell's, not the host's: policy lives here,
mechanism lives in the edition. Private-range and DNS-rebinding
protection is the shell fetcher's responsibility and is documented as
deferred.

### Contribution points

- `export.format`, `import.source`

These gate contribution registration rather than a host import, so
there is no call-site check — a plugin without them simply has its
contribution refused at load.

## Install-time consent (I7.1)

At install, `PluginInstallDialog` shows the requested capabilities:

- **Required permissions** render as an amber-bordered batch panel
  with `AlertTriangle` icon + copy: *"Installing this plugin grants
  every permission in this batch. Cancel to refuse."* The user
  cannot opt out of individual required permissions — accept all or
  cancel.
- **Optional permissions** sit behind a collapsed disclosure
  (`"Show optional permissions"`). Expanding shows a per-capability
  checkbox; the user toggles only what they want to grant. The
  confirm button submits the chosen subset.

On confirm, the host calls `plugin_install(pluginId, grantedOptional)`
on its native side (Tauri command on desktop; HTTP route on web).
The grant set is persisted alongside the install.

## First-use prompt (I7.2)

A plugin runtime-requesting a capability the user skipped at install
gets `FirstUsePermissionPrompt`:

| Choice | Effect |
|---|---|
| **Deny** | Refuses the call. Future requests re-prompt. |
| **Allow once** | Satisfies this call only. Future requests re-prompt. |
| **Allow always** | Satisfies this call AND persists the grant. Future requests skip the prompt. |

There is intentionally no `Deny always` — the three-way shape is
documented in the I7.2 component. Plugins that need a permanent
refusal can be uninstalled via the Permissions panel (I7.3).

## Permissions panel (I7.3 / I7.4)

The Permissions panel is the audit + revoke surface. It renders a
flat table with one row per `(plugin, permission)` pair:

| Kind / Status | Action |
|---|---|
| Required + Granted | **"Uninstall to revoke"** copy (no button — revoke would break the plugin). |
| Required + Pending | **Grant** button (rare; arises if the install was interrupted). |
| Optional + Granted | **Revoke** button (red-bordered). |
| Optional + Revoked | **Grant** button (emerald-bordered). |

The panel also surfaces supervision state (I7.4 / I8.5) — status
pill, crash-budget bar, restart count, and a Re-enable button when
a plugin has been Disabled by the supervisor.

## Runtime enforcement detail

- The host maintains the granted capability set per plugin instance.
- Each host function exposed via WIT performs a capability check
  before executing the underlying operation.
- Failed checks return `PluginError::PermissionDenied`. The plugin
  can recover gracefully + surface a clear message.
- The check happens BEFORE the operation runs — no partial side
  effects can leak through.

## Manifest enforcement detail

- A capability used at runtime but absent from
  `permissions.required` OR `permissions.optional` is rejected at
  the host import. This prevents capability smuggling via crafted
  argv to a subprocess plugin or via a host import callable without
  the explicit grant.
- The manifest parser surfaces typed errors for every malformed
  capability — see I9.3's
  [`tests/capability_enforcement.rs`](https://github.com/plamenix/plamenix-core/blob/main/crates/plamenix-plugin-host/tests/capability_enforcement.rs).

## Trust tiers and capability default-deny

Signature verification (I7.15 + I7.16) sets the trust tier. The
install dialog renders the signature state inline:

| Status | Badge | Effect on install button |
|---|---|---|
| `verified` (signed + signature checks out) | Emerald `ShieldCheck` pill carrying the key id | Enabled. |
| `unsigned` (no `signature.json` in the archive) | Red `ShieldX` pill | Enabled — but user sees red banner copy *"Install only if you trust the source."* |
| `invalid` (signature failed cryptographic verification) | Amber `ShieldAlert` pill, `role="alert"` | Enabled — banner warns of likely tampering. Future M2 setting can disable installs entirely. |

The capability set requested in the manifest is the **maximum** the
plugin can use; the granted set may be smaller. Optional permissions
the user skipped at install + later denied at the first-use prompt
are NOT granted; the manifest declaring them isn't enough.

Trust tier vs default-deny matrix (M1):

| Trust tier | Default for risky capabilities |
|---|---|
| **Verified signature** | Granted on confirm via the install dialog. |
| **Unsigned** | User sees the red banner before granting; required perms still require explicit confirm. |
| **Invalid signature** | Same as unsigned with stronger warning copy. M2 may refuse installs entirely behind a `requireSignature` setting. |

## Where the code lives

| Concern | Crate / file |
|---|---|
| `Permission` enum + parser | `plamenix-plugin-host/src/capability.rs` |
| Manifest enforcement | `plamenix-plugin-host/src/manifest.rs` |
| Subprocess defense-in-depth re-check | `plamenix-plugin-host/src/subprocess.rs` |
| Install dialog | `plamenix-ui/src/plugins/PluginInstallDialog.tsx` |
| First-use prompt | `plamenix-ui/src/plugins/FirstUsePermissionPrompt.tsx` |
| Permissions panel | `plamenix-ui/src/plugins/PermissionsPanel.tsx` |
| Signature verifier | `plamenix-plugin-host/src/signing.rs` |
| Signature banner | `plamenix-ui/src/plugins/PluginInstallDialog.tsx` (`SignatureBanner`) |
| Capability enforcement tests | `plamenix-plugin-host/tests/capability_enforcement.rs` |

## See also

- [`plugin-architecture.md`](./plugin-architecture.md) — wider design.
- [`plugin-manifest.md`](./plugin-manifest.md) — `[permissions]` field
  syntax + every required/optional table layout.
- [`plugin-events.md`](./plugin-events.md) — `permission/*` event
  topics (denied calls, grant changes).
- [`plugin-interceptors.md`](./plugin-interceptors.md) — chain that
  fires before sensitive actions (query.executing, etc.).
