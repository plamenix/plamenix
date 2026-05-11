# 0004. CUPID over SOLID as primary principle frame

Status: Accepted
Date:   2026-05-11

## Context

Plamenix needs a coherent set of code principles that the team and
community contributors can apply consistently. The classical SOLID +
DRY + Clean Code orthodoxy has been heavily critiqued by mature Rust
OSS practitioners (matklad, Carmack, Muratori, Acton). Modern community
consensus has shifted toward CUPID (Dan North, 2021), AHA (Kent Dodds),
and Locality of Behavior (Carson Gross).

## Decision

Adopt **CUPID** as the primary principle frame:

- **C**omposable
- **U**nix philosophy
- **P**redictable
- **I**diomatic
- **D**omain-based

Combined with:

- **AHA** (Avoid Hasty Abstractions) — Rule of Three before extracting.
- **Locality of Behavior** — wins over DRY when they conflict.
- **Deep modules, narrow interfaces** (Ousterhout).

SOLID is **not** rejected wholesale: S (Single Responsibility) and I
(Interface Segregation) survive as part of CUPID's Unix philosophy and
narrow-interface ideals. O / L / D apply only at the three proven
swap-points (`DbDriver`, `PluginHost`, `SecretStore`); preemptively
applying them elsewhere creates ceremony without payback.

## Alternatives considered

- **Strict SOLID + DRY + Clean Code** — produces over-abstracted Rust
  that frustrates contributors. Documented in real-world post-mortems
  (Lobsters, HN). Real Rust OSS (rust-analyzer, jujutsu, helix, lapce,
  zed) explicitly rejects this style.
- **DDD (Domain-Driven Design)** — Plamenix's domain is thin (send
  SQL, render rows). DDD ceremony (entities, value objects,
  aggregates, repositories) adds files without insight.
- **MVC / MVVM** — UI patterns from a different era. React composition
  + hooks already serve this need.
- **CUPID alone, without AHA / LoB** — leaves DRY-vs-locality
  unresolved. The combination is the modern best practice.

## Consequences

- Naming forbids generic suffixes (`Manager`, `Service`, `Provider`)
  without a concrete noun.
- Default code style: concrete, sequential, plain functions. Abstract
  only at proven boundaries.
- Onboarding speed improves; contributors do not need DDD or Clean
  Code familiarity.
- Some patterns that feel "classy" (factories, strategies, decorators)
  are out unless they earn their slot via a concrete need.
- Existing Rust ecosystem code (`tokio`, `serde`, `rsfbclient`) fits
  this style; we are aligned with the community.

## References

- Dan North, "CUPID — for joyful coding":
  https://dannorth.net/blog/cupid-for-joyful-coding/
- Kent C. Dodds, "AHA Programming":
  https://kentcdodds.com/blog/aha-programming
- Carson Gross, "Locality of Behaviour":
  https://htmx.org/essays/locality-of-behaviour/
- John Ousterhout, "A Philosophy of Software Design".
- `docs/principles.md`.
