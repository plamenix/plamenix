# 0015. MIT OR Apache-2.0 dual licence

Status: Accepted
Date:   2026-05-11

## Context

Plamenix is an open-source IDE for Firebird, funded by the Firebird
Foundation and released to the community. We had to pick a licence
before publishing the first commit to a public repo.

Constraints:

- Must not block commercial consulting or paid feature development on
  top of Plamenix.
- Must be compatible with the existing Firebird ecosystem (Firebird
  itself is under the **Initial Developer's Public License (IDPL)**,
  a Mozilla MPL derivative). Firebird tooling like FlameRobin is under
  permissive licences.
- Must align with Rust ecosystem norms, since most of the codebase is
  Rust.

## Decision

Licence Plamenix under **MIT OR Apache-2.0** (the user picks).

Both `LICENSE-MIT` and `LICENSE-APACHE` are committed at the root of
every repo.

`Cargo.toml` files declare:

```toml
license = "MIT OR Apache-2.0"
```

`package.json` files declare:

```json
"license": "(MIT OR Apache-2.0)"
```

## Alternatives considered

- **MIT only** — simpler, but no patent grant. Apache-2.0 has a
  patent clause that protects contributors and users. Industry norm in
  Rust is dual.
- **Apache-2.0 only** — incompatible with GPLv2-only downstreams.
  MIT-or-Apache lets GPLv2 projects pick the MIT branch.
- **MPL-2.0** — would mirror Firebird's IDPL more closely but limits
  static linking and complicates closed-source forks.
- **GPLv3** — would block proprietary plugins and proprietary
  downstream products. Plamenix wants a thriving plugin ecosystem,
  some of which may be proprietary.

## Consequences

- Contributors retain copyright; they grant a dual licence under both
  MIT and Apache-2.0.
- Commercial consulting, support contracts, and proprietary plugins are
  all permitted by the licence.
- The Foundation is comfortable with this choice; permissive licences
  match prior Firebird tooling such as FlameRobin.
- `THIRD-PARTY-NOTICES.md` will track attribution for bundled
  dependencies (notably OpenSSL).
- Every repo includes both `LICENSE-MIT` and `LICENSE-APACHE` files
  at the root, in addition to the `license` field in package metadata.

## References

- Rust API Guidelines: https://rust-lang.github.io/api-guidelines/necessities.html
- FlameRobin (Initial Developer's licence, permissive).
- SPDX identifier: `MIT OR Apache-2.0`.
