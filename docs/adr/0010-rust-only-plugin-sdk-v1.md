# 0010. Rust-only plugin SDK for v1.x

Status: Accepted
Date:   2026-05-11

## Context

The WASM Component Model is language-agnostic. In principle, plugin
authors could write in Rust, Go (TinyGo + `wit-bindgen-go`),
TypeScript / JavaScript (`jco`, `ComponentizeJS`), Python
(`componentize-py`), C / C++, .NET, and others. Each language SDK is a
separate engineering investment: bindings, examples, documentation,
bug fixes, version compatibility.

## Decision

For the `1.0.x` release line, Plamenix officially supports **Rust as
the only plugin SDK language**. The plugin SDK ships as a single Rust
crate (`plamenix-plugin-sdk`) plus a single npm package for the React
half (`@plamenix/plugin-react`).

Other languages may be added in `1.x` and beyond when a community SDK
matures or core-team expertise covers them.

## Alternatives considered

- **Rust + TypeScript + Python SDKs from day one** — multiplies
  surface to maintain by 3× before there is a single plugin in the
  wild. Speculative cost; rejected.
- **WASM only, no SDK** — would force every plugin author to learn
  WIT and `wit-bindgen` by hand. High bar to entry.
- **JavaScript as the only plugin language (Obsidian-style)** — gives
  up the safety and capability story of WASM. Plamenix gets the best
  story by being WASM-first with one well-supported language.

## Consequences

- Plugin authors who do not know Rust cannot ship Plamenix plugins in
  `1.0.x`. Pragmatic for a Foundation-funded DB tool — the relevant
  contributor pool already knows Rust or C++.
- Documentation, examples, and tooling investment focus on one path.
  Quality goes up faster than if spread thin.
- Future SDKs in other languages will be **community contributions**
  unless core-team has capacity to maintain them. We never ship an
  SDK we cannot fix bugs in.
- The WIT contract is stable across SDKs, so adding a second SDK does
  not require breaking changes.

## References

- `docs/plugin-system.md`.
- Zed extensions: shipped Rust-only first, added other languages
  only after the Rust path stabilised.
