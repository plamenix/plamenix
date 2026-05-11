# Versioning

Plamenix follows [SemVer 2.0.0](https://semver.org/) strictly.

## Current line

```
1.0.0-beta              ← starting release
1.0.0-beta.1
1.0.0-beta.2
…
1.0.0-rc.1              ← API freeze
1.0.0-rc.2
1.0.0                   ← stable
1.0.1                   ← patch
1.1.0                   ← additive feature
2.0.0                   ← breaking change
```

We **skip the `0.x` line entirely.** Public release starts at
`1.0.0-beta`, then runs through betas and release candidates to `1.0.0`
stable. The `0.0.1-beta` from the MVP (`firebird-web-client`) is not
carried forward; Plamenix begins a fresh version line.

## Precedence (SemVer §11)

```
1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-beta < 1.0.0-beta.1 < 1.0.0-rc.1 < 1.0.0
```

We skip the `alpha` line. Plamenix starts at `1.0.0-beta`.

## Lockstep across repos

All five sibling repos share the same version line:

- `plamenix` (meta-workspace, internal use only — `MILESTONES.md`
  tracks the line for the whole project)
- `plamenix-core`
- `plamenix-ui`
- `plamenix-desktop`
- `plamenix-web`

Workspace versions are set once in each repo's root configuration:

- **Rust** — `Cargo.toml` `[workspace.package] version = "1.0.0-beta"`;
  member crates set `version.workspace = true`.
- **TypeScript** — `package.json` `"version": "1.0.0-beta"`.

A version bump touches every repo. Tooling will help (`release-plz`
for Rust, `changesets` for npm, optionally `covector` for cross-repo
coordination).

## Cargo workspace versions

```toml
[workspace.package]
version = "1.0.0-beta"

[package]
version.workspace = true
```

Never set per-crate `version = "..."` strings outside `Cargo.lock`.
Lockstep is enforced by the workspace inheritance.

## API stability commitments

- **Within the `1.0.0-beta.x` line**: breaking changes are permitted.
  Plugin authors should expect occasional API churn. Beta = "we know
  what 1.0 looks like, polishing remains."
- **From `1.0.0-rc.1` onward**: API freeze. Only bug fixes between
  `rc` releases.
- **From `1.0.0`**: no breaking changes without a major-version bump
  to `2.0.0`. Deprecations get at least three minor releases of
  warning.

## Plugin API versioning (separate)

The plugin API (WIT contract) carries its **own** semver line,
independent of the Plamenix host version:

```
plugin-api@1.0
plugin-api@1.1
plugin-api@2.0       ← breaking; old plugins still loaded if host binds 1.x interface
```

The host can bind multiple interface versions simultaneously, so a
plugin targeting `plugin-api@1.0` keeps working when the host moves to
`plugin-api@2.0`. See [plugin-system.md](./plugin-system.md) and
[plugin-manifest.md](./plugin-manifest.md).

## Git tags

Tags shipped from each sibling repo:

```
v1.0.0-beta
v1.0.0-beta.1
…
v1.0.0-rc.1
v1.0.0
```

Build metadata for CI artifacts uses the SemVer-2.0 `+build.x` suffix:
`1.0.0-beta+build.123`. Build metadata is informational only; it does
not affect precedence.

## Tooling

- **`release-plz`** — Rust workspace versioning, generates
  `CHANGELOG.md` from Conventional Commits, publishes to crates.io
  (once GitHub is live).
- **`changesets`** — TypeScript packages (`@plamenix/ui`, etc.).
- **`covector`** — Tauri-proven tool for coordinated multi-repo
  releases; may be adopted once five-repo coordination becomes
  routine.

## Pre-1.0 timeline

| Stage | When | Notes |
|-------|------|-------|
| `1.0.0-beta` | Mid-June 2026 | First public release (per `MILESTONES.md`). |
| `1.0.0-beta.x` | Through summer 2026 | Bug fix and feedback cycle. Breaking changes allowed. |
| `1.0.0-rc.1` | TBD | API freeze. |
| `1.0.0` | TBD | Stable. Long-term API stability commitments begin. |

`MILESTONES.md` is the canonical roadmap; this document only describes
the versioning *model* applied to it.
