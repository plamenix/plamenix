# 0018. pnpm as sole supported package manager

Status: Accepted
Date:   2026-05-11

## Context

Plamenix has three Node-touching repos (`plamenix-ui`, `plamenix-web`,
and the renderer-process portion of `plamenix-desktop`). Each one will
publish artifacts to npm and consume the others either from npm or
from local sibling repos during development.

Three serious candidates in 2026:

- **npm** — bundled with Node, slowest, no native workspace protocol
  parity with pnpm/yarn.
- **yarn (berry / 4.x)** — Plug'n'Play and zero-installs introduce a
  resolution model that breaks tools that expect `node_modules/`.
- **pnpm** — content-addressable store, hard-linked `node_modules/`,
  strict peer dependency resolution, native workspace + catalog support.

## Decision

**pnpm** is the only supported package manager. Pinned via `packageManager`
field in every `package.json`:

```json
"packageManager": "pnpm@10.0.0"
```

Lock file (`pnpm-lock.yaml`) is committed in every Node-touching repo.

Local cross-repo development uses **pnpm overrides / `pnpm link`**, not
npm `link`, not yarn portal protocol.

CI installs pnpm via Corepack (now stable in Node 22+) before running
`pnpm install --frozen-lockfile`.

## Alternatives considered

- **npm** — works, but loses pnpm's strict resolution (catches phantom
  dependencies) and content-addressable disk usage benefits.
- **yarn berry** — PnP breaks Tauri build, `vite-plugin-dts`, and
  several React tooling assumptions. Hard pass.
- **bun** — fast, but its package manager is still settling in 2026
  and its lockfile format is opaque. Reconsider in v2.x.
- **Support multiple** — package manager pluralism creates "works on
  my machine" bugs around peer dependency resolution. One PM, one lock
  format, one CI invocation. Far less friction.

## Consequences

- Contributors must install pnpm (`corepack enable` handles it once
  Node is installed).
- `CONTRIBUTING.md` says pnpm only and gives the Corepack one-liner.
- CI workflows install pnpm before `pnpm install`.
- Lockfile diffs are smaller and easier to review than npm's.
- Phantom dependencies surface during `pnpm install` instead of at
  runtime, catching them earlier.
- `pnpm catalog:` syntax may be used to pin shared peer versions
  across the three Node repos when version drift becomes a concern.

## References

- pnpm docs: https://pnpm.io/
- Corepack: https://nodejs.org/api/corepack.html
- "Why pnpm" comparison:
  https://pnpm.io/motivation
