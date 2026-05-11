# 0012. Specta-generated TypeScript types

Status: Accepted
Date:   2026-05-11

## Context

Plamenix's React shell talks to a Rust backend via an IPC boundary
(Tauri `invoke` on desktop, HTTP `fetch` on web). Both sides share the
same data shapes (`ConnectionConfig`, `SessionId`, `QueryResult`,
`PluginManifest`, etc.). Without automation, the TypeScript types
inevitably drift from the Rust types, producing runtime errors that
type checkers cannot catch.

## Decision

Rust types in `plamenix-core` (and any other crate that crosses the
boundary) derive `specta::Type`. The build process emits TypeScript
declarations via [`specta`](https://github.com/specta-rs/specta) and
publishes them as part of `@plamenix/ui` (or, if scope grows, a
separate `@plamenix/types` npm package).

Frontend code imports the generated types directly:

```ts
import type { ConnectionConfig, QueryResult } from '@plamenix/types';
```

Renaming or changing a Rust type produces a TypeScript compile error
in the same PR, on the front-end side.

## Alternatives considered

- **Hand-written TypeScript types matching the Rust** — the MVP did
  this. Drift was a real source of bugs.
- **JSON Schema-based codegen** — heavier toolchain, less idiomatic
  for Tauri / NAPI integration.
- **TauRPC** — builds on top of Specta and could be adopted later.
  Specta on its own is the minimum we need; TauRPC adds typed command
  dispatch which we may want once command count grows.
- **`tsify` / similar wasm-bindgen tools** — solve a different
  problem (bindgen for JS calling WASM).

## Consequences

- Type drift impossible by construction.
- `specta` is pre-1.0 (`1.0.5` stable at audit time, `2.0-rc`
  exists); we pin exact and watch the upgrade.
- Build pipeline must run the Specta export step before the
  TypeScript build.
- All shared shapes must be `serde`-friendly and `specta`-friendly
  (no exotic Rust types in IPC payloads).
- A small subset of Rust types may not be expressible in TypeScript
  cleanly; those stay internal and never cross the boundary.

## References

- `docs/transport.md`, `docs/state-model.md`.
- Specta: https://github.com/specta-rs/specta
- TauRPC: https://github.com/MatsDK/TauRPC
