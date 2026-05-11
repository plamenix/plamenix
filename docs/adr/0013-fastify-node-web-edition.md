# 0013. Fastify + Node for the web edition

Status: Accepted
Date:   2026-05-11

## Context

Plamenix's web edition needs a server that serves the React UI bundle
and exposes the same use-case surface that Tauri's `#[tauri::command]`
handlers expose on desktop. Options were:

1. Reuse the Rust `plamenix-core` crates server-side via an Axum or
   Actix HTTP server (one shared backend stack across editions).
2. Run a Node.js + Fastify server, calling into `plamenix-core` via
   NAPI bindings.
3. Run a Node.js + Fastify server with a parallel JavaScript driver
   (e.g., `node-firebird`).

## Decision

Use **Fastify on Node.js**. The Fastify server calls into
`plamenix-core` via **NAPI bindings** to `rsfbclient` published as
`@plamenix/fbclient-node`.

This preserves a single driver implementation (rsfbclient) across both
editions and lets Plamenix benefit from the npm ecosystem (Fastify
plugins, auth middleware, Docker tooling) on the web side.

## Alternatives considered

- **Axum / Actix Rust server** — single backend stack but loses the
  npm ecosystem advantages on the server side, and the Foundation
  contributor pool is more comfortable with Node than Rust HTTP
  frameworks.
- **Fastify + `node-firebird`** — the MVP path. Driver quirks (MON$,
  BLOB callbacks, BOOLEAN params, ARRAY descriptors) we are explicitly
  leaving behind. Two different driver behaviours across editions.
- **Express** — Fastify is faster, more modern, better TypeScript
  support, similar developer experience.
- **HTTP-only proxy to a Rust subprocess** — heavyweight per request
  IPC; worse than direct NAPI.

## Consequences

- Web edition's contributor surface is JavaScript / TypeScript +
  Fastify, lower bar to entry than a Rust HTTP server.
- A NAPI binding (`@plamenix/fbclient-node`) must be built and
  published as a native-module npm package. Adds CI complexity for
  cross-platform native binaries.
- All driver-level fixes land once in `plamenix-core` and both
  editions benefit.
- Desktop and web editions diverge only in their transport layer and
  edition-specific concerns (auth model, system access).

## References

- `docs/three-editions.md`, `docs/napi-rsfbclient.md`,
  `docs/transport.md`.
- `MILESTONES.md` — M1 calls out Fastify explicitly.
