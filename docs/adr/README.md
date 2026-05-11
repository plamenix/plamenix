# Architecture Decision Records

Lightweight records of significant architectural choices made during
Plamenix design. Each ADR captures **why** a decision was made, the
alternatives considered, and the consequences.

ADRs are numbered, never renumbered. Superseded ADRs stay in place;
their status is updated and they reference the superseder.

## Format

Every ADR follows this template:

```
# <number>. <short title>

Status: <Accepted | Superseded by NNNN | Rejected>
Date:   YYYY-MM-DD

## Context
<What was the situation, what forces applied?>

## Decision
<What did we decide to do?>

## Alternatives considered
<What else did we look at, and why did we reject each?>

## Consequences
<What changes because of this decision, positive or negative?>

## References
<Links to discussions, supporting docs, external sources.>
```

## Index

| # | Title | Status |
|---|-------|--------|
| 0001 | [Tauri shell, not Electron](./0001-tauri-not-electron.md) | Accepted |
| 0002 | [rsfbclient native with `with_dyn_load`](./0002-rsfbclient-native-with-dyn-load.md) | Accepted |
| 0003 | [WASM Component Model for plugins](./0003-wasm-component-model-plugins.md) | Accepted |
| 0004 | [CUPID over SOLID as primary principle frame](./0004-cupid-over-solid.md) | Accepted |
| 0005 | [Pragmatic hexagonal — three traits at swap-points only](./0005-pragmatic-three-traits.md) | Accepted |
| 0006 | [Microkernel — core surfaces stay in core](./0006-microkernel-core-stays-core.md) | Accepted |
| 0007 | [Polyrepo with no git submodules](./0007-polyrepo-no-submodules.md) | Accepted |
| 0008 | [JetBrains-style splash window on desktop](./0008-jetbrains-style-splash.md) | Accepted |
| 0009 | [Tabs from day one](./0009-tabs-day-one.md) | Accepted |
| 0010 | [Rust-only plugin SDK for v1.x](./0010-rust-only-plugin-sdk-v1.md) | Accepted |
| 0011 | [Zustand for shared React state, not Context](./0011-zustand-not-context.md) | Accepted |
| 0012 | [Specta-generated TypeScript types](./0012-specta-generated-types.md) | Accepted |
| 0013 | [Fastify + Node for the web edition](./0013-fastify-node-web-edition.md) | Accepted |
| 0014 | [NAPI bindings to rsfbclient for Node](./0014-napi-rsfbclient-bindings.md) | Accepted |
| 0015 | [MIT-or-Apache-2.0 dual licence](./0015-mit-apache-dual-license.md) | Accepted |
| 0016 | [OS keyring for encryption secrets from day one](./0016-encryption-os-keyring-day-one.md) | Accepted |
| 0017 | [ESM-only React library](./0017-esm-only-ui-library.md) | Accepted |
| 0018 | [pnpm as the only supported Node package manager](./0018-pnpm-package-manager.md) | Accepted |
| 0019 | [Defer Plamenix-as-client-keyholder integration](./0019-defer-client-keyholder-integration.md) | Accepted |
