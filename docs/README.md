# Plamenix — Architectural & Technical Documentation

This directory holds the design decisions that shape Plamenix. Files here
are not auto-loaded into Claude sessions; they are read on demand, by
humans and by Claude alike, when context is needed for a specific topic.

These documents capture **decisions already made**. They are not a
roadmap (see [`../MILESTONES.md`](../MILESTONES.md)) and not speculative
exploration — every line reflects a choice the project has committed to.

## Index

### Architecture & principles

- [architecture.md](./architecture.md) — Overall mental model, five-repo
  polyrepo split, transport-agnostic UI shell.
- [principles.md](./principles.md) — CUPID, AHA, Locality of Behavior,
  naming, comments. Why these, not SOLID/DRY/Clean Code.
- [three-editions.md](./three-editions.md) — Desktop vs Web edition
  capability matrix.

### Plugin system

- [plugin-system.md](./plugin-system.md) — WASM Component Model + ESM
  React contributions. Why this, not dylib/subprocess/scripting.
- [contribution-points.md](./contribution-points.md) — Full enumeration
  of slots plugins fill.
- [plugin-manifest.md](./plugin-manifest.md) — `manifest.toml` schema.
- [capability-model.md](./capability-model.md) — Permission grammar,
  install-time consent.

### Runtime & state

- [transport.md](./transport.md) — Transport abstraction (Tauri invoke
  vs HTTP fetch), Specta type generation.
- [state-model.md](./state-model.md) — Zustand stores, per-tab
  isolation, TanStack Query keys.
- [splash-window.md](./splash-window.md) — JetBrains-style splash
  window, plugin loading flow.

### Firebird

- [firebird-driver.md](./firebird-driver.md) — rsfbclient native + pure
  Rust, `with_dyn_load`, bundled fbclient strategy.
- [firebird-quirks.md](./firebird-quirks.md) — node-firebird quirks
  superseded by native fbclient; rsfbclient status.
- [encryption.md](./encryption.md) — Firebird encryption, DbCrypt +
  KeyHolder plugins, IBSurgeon EPF, M1 minimum scope.
- [napi-rsfbclient.md](./napi-rsfbclient.md) — NAPI bindings so the
  web edition uses the same driver as desktop.

### Process

- [versioning.md](./versioning.md) — SemVer 2.0.0, `1.0.0-beta` line,
  lockstep across repos.
- [git-workflow.md](./git-workflow.md) — Conventional Commits, branch
  names, no submodules.
- [release-targets.md](./release-targets.md) — Build matrix per
  platform (Windows MSI, macOS DMG, Linux AppImage / .deb, Docker).

### ADRs

[Architecture Decision Records](./adr/README.md) — numbered, lightweight
records of significant choices. Read these for the *why* behind each
decision and the alternatives considered.

## How to keep this directory honest

- Update a document when its decision changes. Stale specs are worse
  than missing ones.
- Add a new document when a new decision is made that affects future
  work. Do not write speculative documents.
- Add an ADR when a decision involves a meaningful trade-off or
  rejected alternative worth recording. Routine changes do not need
  ADRs.
- Cross-reference from a sibling repo's `CLAUDE.md` with
  `../plamenix/docs/<topic>.md` when relevant. Per-repo specifics stay
  in the repo's own files; cross-cutting decisions live here.
