# Principles

Plamenix is built on a pragmatic-modern stack of code principles, not the
classical SOLID / DRY / Clean-Code orthodoxy. The principles below are
the ones that survived honest comparison and that we apply with
judgement, not as dogma.

## CUPID over SOLID

[CUPID](https://dannorth.net/blog/cupid-for-joyful-coding/) (Dan North,
2021+) replaces SOLID as the primary frame.

| Letter | Property | Plamenix application |
|--------|----------|---------------------|
| **C** | Composable — modules combine without surprise | Feature crates compose at the composition root; plugins compose via slots. |
| **U** | Unix philosophy — do one thing well | One crate per feature. One function per job. No god types. |
| **P** | Predictable — does what the name implies; no hidden effects | Function name = contract. Side effects visible in signature. |
| **I** | Idiomatic — looks like the language | Rust: ownership-first, iterator chains, `?` propagation. React: hooks + composition. No Java-Rust, no class-React. |
| **D** | Domain-based — speaks the problem | Types named in Firebird vocabulary (`Trigger`, `Generator`, `RDB$RELATION_NAME`), not generic enterprise nouns. |

SOLID's S (Single Responsibility) survives as part of CUPID's Unix
philosophy. SOLID's I (Interface Segregation) survives in "narrow
interfaces." The O, L, D principles apply only at the three swap-points
where substitutability is concretely needed; elsewhere they create
ceremony without payback.

## AHA — Avoid Hasty Abstractions

[AHA Programming](https://kentcdodds.com/blog/aha-programming) (Kent C.
Dodds) replaces dogmatic DRY.

- **Default**: concrete and possibly duplicated.
- **Rule of Three**: extract on the third occurrence, not the first.
- **Wrong abstraction > duplication**: unwinding a wrong abstraction is
  surgery; deleting a duplicate is trivial.

Sandi Metz's "duplication is far cheaper than the wrong abstraction"
captures the trade-off.

## Locality of Behavior

[Locality of Behavior](https://htmx.org/essays/locality-of-behaviour/)
(Carson Gross) beats DRY when they conflict.

- The behaviour of a unit should be obvious by reading that unit.
- Long, linear functions with visible logic beat short functions with
  hidden indirection.
- Inline style / handlers / queries near the component that uses them,
  rather than relocating into shared modules for the sake of relocation.

## Deep modules, narrow interfaces

[A Philosophy of Software Design](https://web.stanford.edu/~ouster/cgi-bin/aposd.php)
(John Ousterhout). A good module hides complexity rather than relocating
it. Few public symbols; rich behaviour behind them. Avoid "classitis"
— many shallow classes that pile up cognitive load.

## Clean-Code backlash

The Robert Martin "Clean Code" style is rejected as universal advice:

- "Small functions are virtuous" is not universal. Carmack: large
  methods are fine if behaviour is local.
- Casey Muratori: fragmented Clean Code causes measurable 10× perf
  hits.
- Mike Acton, Jonathan Blow (data-oriented design): reject heavy SOLID
  / DI abstraction layers entirely.

Plamenix follows the modern consensus: pragmatic concrete code with
SOLID-style discipline only at proven boundaries.

## Naming

- Names speak the Firebird domain. `Trigger`, `Generator`, `Domain`,
  `RDB$RELATION_NAME`.
- Banned without a concrete noun: `Manager`, `Service`, `Provider`,
  `Helper`, `Handler`. `QueryQueue` is fine; `QueryManager` is not.
- Booleans: `is_*`, `has_*`, `should_*`, `can_*`.
- Functions = verbs. Types = nouns.
- No abbreviations except universal ones (`id`, `db`, `ui`, `sql`,
  `ddl`, `fb`, `ipc`, `fs`, `os`).

## Comments

- Default: **no comments**.
- Add one only when **why** is non-obvious: upstream bug, hidden
  invariant, surprising behaviour, `SAFETY:` block for `unsafe`.
- Never add **what** comments. Code says what; identifier names say
  what.
- No file headers. No license per file (`LICENSE-*` at repo root
  suffices). No section dividers (`// === Stuff ===`) except in files
  over 300 LOC where they aid scanning.

## Errors

- Library code: `thiserror` typed enums; callers can match and
  recover.
- Binary code: `anyhow` for context-rich, user-facing messages.
- Never mix within a layer.
- Never `unwrap` / `expect` / `panic!` outside tests, examples, benches,
  or with a `SAFETY:` / `INVARIANT:` comment justifying it.

## Public API discipline

- Every `pub` item earns rustdoc: summary, `# Errors` when applicable,
  `# Examples` when usage is non-obvious, `# Safety` required for
  `unsafe`.
- `#![warn(missing_docs)]` at crate roots enforces the discipline.
- Doctests are part of the contract; they compile and run in CI so
  examples never rot.

## Self-explanatory + SOLID + minimal abstractions + AHA

These principles are mutually compatible when applied with judgement:

- **Boundary?** → apply SOLID (trait at swap-point).
- **Inside a module?** → concrete, sequential, plain functions.
- **Duplication 1–2 times?** → leave it.
- **Duplication 3+ times?** → extract.
- **Locality vs DRY?** → Locality wins.
- **Self-explanatory vs SOLID at edge?** → split at natural seams, not
  by metrics.

No contradiction in practice. Real tension only at edges, resolved by
the rules above.
