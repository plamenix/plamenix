# 0005. Pragmatic hexagonal — three traits at swap-points

Status: Accepted
Date:   2026-05-11

## Context

Plamenix originally considered a strict hexagonal split: a `domain`
crate, a `ports` crate, an `application` crate, and per-concern
`adapter` crates. Research into how mature Rust OSS projects (rust-
analyzer, jujutsu, helix, lapce, zed, biome) structure themselves
showed they overwhelmingly **avoid** strict hexagonal in Rust because:

- Trait indirection multiplies file counts for simple changes.
- Generic bound puzzles slow contributors.
- Rust's custom-derive ecosystem conflicts with hexagonal indirection
  (Eizinger, 2024).
- A 260-LOC service ballooning to 750 LOC across 20 files for the sake
  of "testability" is a documented anti-pattern.

The same research showed that real codebases extract traits **at known
swap-points only**, keeping the rest of the system flat and concrete.

## Decision

Plamenix uses **traits at exactly three swap-points**:

1. **`DbDriver`** — rsfbclient today, alternative drivers and
   plugin-supplied drivers possible later.
2. **`PluginHost`** — wasmtime today, isolation discipline and
   future testability.
3. **`SecretStore`** — in-memory + OS keyring backends.

Everything inside feature crates is **concrete functions on concrete
types**. No `application` layer, no generic `UseCase<R, A, P>` trait,
no anemic types-plus-services split.

## Alternatives considered

- **Strict hexagonal** — rejected per the research summary above.
- **Single flat crate** — too coarse-grained for a project that grows
  to ~7 feature areas. Compilation times and code navigation suffer.
- **Workspace with per-feature crates AND ports/application/adapter
  abstractions** — combines the worst of both: coarse boundary AND
  fine-grained indirection.

## Consequences

- Typical PR touches 1–3 files instead of 6+.
- Three fake implementations cover every isolation-testing need
  (`FakeDbDriver`, `FakePluginHost`, `FakeSecretStore`).
- Plugin authors never see internal traits; the plugin SDK is its own
  surface.
- New crates accrete under `crates/` only when a concrete feature
  forces the split, not preemptively.
- If a fourth real swap-point appears, we will add a fourth trait at
  that time — not before.

## References

- matklad on rust-analyzer architecture.
- jujutsu, helix, zed architecture docs.
- Thomas Eizinger, "Rust's custom derives in a hexagonal architecture
  — incompatible ideas":
  https://blog.eizinger.io/5835/rust-s-custom-derives-in-a-hexagonal-architecture-incompatible-ideas
- Lobsters: "Never use hexagonal architecture" discussion.
- `docs/architecture.md`, `docs/principles.md`.
