# Plamenix

A community-driven open-source IDE for Firebird databases. Funded by the
[Firebird Foundation](https://firebirdsql.org/en/firebird-foundation/).

Plamenix ships as a **desktop application** (Tauri 2 + Rust) and a
**web edition** (Fastify + React) from a shared codebase. Both editions
talk to Firebird through [`rsfbclient`](https://github.com/fernandobatels/rsfbclient).

## Repositories

This repo (`plamenix/`) is the **meta-workspace**. The actual product is
spread across five sibling repositories that live next to this one in the
same parent directory:

| Repo | Contents |
|------|----------|
| `plamenix/` | This repo — orchestration, milestones, contributor docs. |
| `plamenix-core/` | Shared Rust crates: types, db driver wrapper, plugin host, plugin SDK. |
| `plamenix-ui/` | Shared React library: shell, components, hooks, transport abstraction. |
| `plamenix-desktop/` | Tauri 2 desktop edition. |
| `plamenix-web/` | Fastify + React web edition (self-hostable). |

## Quick start

```sh
git clone <plamenix-meta-workspace-url> plamenix
cd plamenix
just setup       # clones sibling repos, wires local path overrides
just dev         # runs the desktop edition against local siblings
```

(Until the public release infrastructure is live, sibling repos are local
only. See `CONTRIBUTING.md` for the bootstrap procedure.)

## Roadmap

See [`MILESTONES.md`](./MILESTONES.md). Current target: `1.0.0-beta` in
mid-June 2026.

## Licence

Plamenix is dual-licensed under **MIT OR Apache-2.0**. Choose whichever
suits your use.

See [`LICENSE-MIT`](./LICENSE-MIT) and [`LICENSE-APACHE`](./LICENSE-APACHE).

## Code of Conduct

This project follows the [Contributor Covenant](./CODE_OF_CONDUCT.md).
By participating, you agree to abide by its terms.
