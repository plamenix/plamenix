# 0014. NAPI bindings to rsfbclient for Node

Status: Accepted
Date:   2026-05-11

## Context

The Fastify web edition needs a Firebird driver. The desktop edition
uses `rsfbclient` (Rust). Plamenix wants **one driver implementation**
so that quirks, bug fixes, and feature work happen once and benefit
both editions.

## Decision

Build **NAPI bindings** that expose `rsfbclient` (or a thin
`plamenix-core` wrapper of it) to Node.js. Published as a native npm
package: **`@plamenix/fbclient-node`**.

The bindings use [`napi-rs`](https://napi.rs/) — the modern toolchain
for Rust → Node native modules. Pre-built native binaries are shipped
per platform / arch as platform-tagged optional dependencies, following
`napi-rs` convention.

## Alternatives considered

- **Keep `node-firebird` for the web edition** — accumulates all the
  MVP quirks (MON$ crashes, BLOB callback, BOOLEAN params, ARRAY
  descriptors). Splits driver behaviour across editions. Explicitly
  rejected when MILESTONES was clarified.
- **Run a Rust HTTP / gRPC sidecar process under Fastify** —
  heavyweight per-request IPC, worse than NAPI, harder to package.
- **Switch the web edition to Axum / Actix instead of Fastify** —
  considered and rejected in ADR 0013; we keep Fastify on Node.
- **Use `neon` instead of `napi-rs`** — older crate, less active
  ecosystem in 2026.

## Consequences

- One driver implementation. One quirks list. One truth.
- The CI pipeline must build native bindings on Linux (x64 / arm64),
  macOS (x64 / arm64), and Windows (x64). `napi-rs` handles this with
  reasonable workflow templates.
- npm publishing adds platform-tagged native modules. Consumers install
  the right one automatically.
- The binding lives **inside `plamenix-web/`** initially. If demand
  grows for the binding outside Plamenix, it can be split into its
  own `plamenix-fbclient-node` repo.
- Async handling: `rsfbclient` is synchronous, so the binding wraps
  every call in a Tokio blocking worker on the Rust side and returns
  a real JS `Promise` to Node.

## References

- `docs/napi-rsfbclient.md`, `docs/firebird-driver.md`,
  `docs/three-editions.md`.
- napi-rs: https://napi.rs/
