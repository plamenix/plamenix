# 0017. ESM-only `@plamenix/ui` library

Status: Accepted
Date:   2026-05-11

## Context

`plamenix-ui` is the shared React component library imported by both
the desktop edition (Tauri renderer process) and the web edition
(Fastify-served SPA). It also exposes the `Transport` interface that
abstracts over `tauri.invoke` vs `fetch`.

Node.js shipped ESM as stable in v12 (2019); by 2026, the Node and npm
ecosystem is solidly ESM-first. Vite, Vitest, ESLint flat config,
Prettier 3 are all ESM.

## Decision

`@plamenix/ui` is **ESM-only**. No CommonJS build. No dual-package
hazard.

```json
{
  "name": "@plamenix/ui",
  "type": "module",
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "import": "./dist/index.mjs"
    }
  }
}
```

- No `"main"` field — only `"exports"`.
- No CJS sibling bundle (`.cjs`).
- TypeScript output target: `ES2024`, module: `ESNext`.
- All consumers must support ESM (they do: Tauri renderer is Vite,
  Fastify supports ESM with `"type": "module"`).

## Alternatives considered

- **Dual CJS + ESM build** — produces dual-package hazard, doubles
  build time, doubles bundle inspection surface, adds tsup or
  rollup-plugin complexity. Pointless when both consumers are ESM.
- **CJS only** — would force the rest of the stack to follow. Goes
  against ecosystem direction.
- **Single index.js (no exports field)** — works but skips the
  `"exports"` benefits: enforced public API, conditional resolution
  for types, future-proof for subpath exports (`@plamenix/ui/transport`).

## Consequences

- Consumers must use ESM imports. This is already true for Vite +
  Fastify ESM, so there is no migration cost.
- Library build configuration is simpler: one Vite library build,
  one output, one `.d.ts` bundle via `vite-plugin-dts`.
- Anyone trying to `require()` `@plamenix/ui` from CJS will get a
  clear error from Node. The README documents ESM-only.
- Subpath exports (`@plamenix/ui/transport`) are available later
  without restructuring.

## References

- Node.js ESM docs: https://nodejs.org/api/esm.html
- "Pure ESM package" pattern (Sindre Sorhus):
  https://gist.github.com/sindresorhus/a39789f98801d908bbc7ff3ecc99d99c
